# 可观测性（指标与日志）- Elixir 实现

| 项 | 内容 |
|------|------|
| 语言 | Elixir |
| 设计文档 | [observability.md](../../design/observability.md) |
| Roadmap | Phase 2（P2-08、P2-09）、Phase 3（P3-10）、Phase 9（P9-05） |

---

## 1. 模块结构

```
lib/im/
  ├── log.ex                    # 统一日志入口 IM.Log（宏 API）
  ├── log/
  │   ├── metadata.ex           # Logger.metadata 管理
  │   └── rate_limit.ex         # auth_failed / rate_limited 采样
  └── telemetry/
      ├── supervisor.ex
      ├── metrics.ex               # Prometheus 定义（DD-028 名）
      ├── tags.ex                  # host / node / cmd / msg_type
      ├── websocket.ex             # packet received/sent/error + handler
      ├── message.ex               # ack latency stages
      └── connection.ex            # connections.total + auth.total
```

**落地状态**：Wave1–5 已对齐——宏日志、生产 NDJSON、核心/存储/投递/出站/跨节点/burn 指标；`IM.Audit`；§2.6.4 失败路径日志 + REST `LogContext` + 登出审计。  
Application 启动时挂 `IM.Log.RateLimit` + `IM.Telemetry.Supervisor`；Handler 入口 `IM.Log.Metadata.set_from_packet/2`。

---

## 2. 依赖

```elixir
# mix.exs（Phase 9 生产导出）
{:telemetry, "~> 1.3"},
{:telemetry_metrics, "~> 1.1"},
{:telemetry_poller, "~> 1.1"},
{:telemetry_metrics_prometheus, "~> 1.1", only: :prod}
```

Phase 2–3 仅需 `:telemetry`（OTP 自带），测试用 `:telemetry_test` 或手动 attach。

生产 JSON 日志（可选）：

```elixir
{:logger_json, "~> 6.0", only: :prod}
```

---

## 3. 统一日志 `IM.Log`

业务代码 **不直接** `Logger.*`。`IM.Log` 负责：**级别门控**、**生产白名单**、**高频采样**、**惰性求值**、**调用点定位**。

`IM.Log.warning/2` 等对外 API **必须是宏**（`defmacro`），在展开时经 `__CALLER__` 注入 `caller_module` / `caller_file` / `caller_line`。若用普通函数再调 `Logger`，Elixir 会把 `:module` / `:line` 记在 `IM.Log` 内部，业务调用点信息丢失。

```elixir
defmodule IM.Log do
  @moduledoc """
  结构化日志门面。生产默认 level :warning，仅白名单 event。
  对外 API 为宏，保留业务调用点。设计见 docs/design/observability.md §2.6
  """

  require Logger

  @prod_allowed ~w(
    packet_decode_error storage_failed push_failed cluster_dispatch_failed
    handler_crash internal_error packet_error auth_failed rate_limited
    channel_subscribe_denied channel_publish_dropped channel_push_failed
  )a

  defmacro info(event, fields \\ []) do
    quote bind_quoted: [event: event, fields: fields, caller: __CALLER__] do
      IM.Log.__log__(:info, event, fields, caller)
    end
  end

  defmacro warning(event, fields \\ []) do
    quote bind_quoted: [event: event, fields: fields, caller: __CALLER__] do
      IM.Log.__log__(:warning, event, fields, caller)
    end
  end

  defmacro error(event, fields \\ []) do
    quote bind_quoted: [event: event, fields: fields, caller: __CALLER__] do
      IM.Log.__log__(:error, event, fields, caller)
    end
  end

  defmacro debug(event, fields \\ []) do
    quote bind_quoted: [event: event, fields: fields, caller: __CALLER__] do
      IM.Log.__log__(:debug, event, fields, caller)
    end
  end

  @doc false
  def __log__(level, event, fields, %Macro.Env{} = caller) when is_atom(event) do
    fields = fields |> caller_fields(caller) |> trim_reason()

    if Logger.enabled?(level) and allowed?(level, event) and sample?(event, fields) do
      metadata = Keyword.put(fields, :event, event)
      Logger.log(level, fn -> Atom.to_string(event) end, metadata)
    end

    :ok
  end

  defp caller_fields(fields, %Macro.Env{} = caller) do
    Keyword.merge(fields, [
      caller_module: caller.module,
      caller_file: Path.basename(caller.file),
      caller_line: caller.line
    ])
  end

  # 生产 (:warning) 下 info/debug 全部丢弃；warning/error 须在白名单
  defp allowed?(:info, _event), do: not prod?()
  defp allowed?(:debug, _event), do: not prod?()
  defp allowed?(level, event) when level in [:warning, :error] do
    not prod?() or event in @prod_allowed
  end
  defp allowed?(_, _), do: true

  defp prod?, do: Application.get_env(:im, :env) == :prod

  defp sample?(:auth_failed, fields), do: IM.Log.RateLimit.allow?(:auth_failed, fields)
  defp sample?(:rate_limited, fields), do: IM.Log.RateLimit.allow?(:rate_limited, fields)
  defp sample?(_, _), do: true

  # 限制 reason 长度，避免 inspect 大 term 阻塞
  defp trim_reason(fields) do
    case Keyword.fetch(fields, :reason) do
      {:ok, reason} when is_binary(reason) ->
        Keyword.put(fields, :reason, String.slice(reason, 0, 200))

      {:ok, reason} ->
        Keyword.put(fields, :reason, reason |> inspect() |> String.slice(0, 200))

      :error ->
        fields
    end
  end
end
```

**验收**：在 `IM.Services.MessageSend` 中调用 `IM.Log.warning(:packet_error, [])`，输出 JSON 的 `caller_module` 必须为 `Elixir.IM.Services.MessageSend`，`caller_line` 为调用行号，**不得**为 `IM.Log`。

### 3.1 使用约定

```elixir
# 生产会输出（warning）
IM.Log.warning(:auth_failed, reason: :invalid_token, app_key: app_key)

# 生产会输出（error）
IM.Log.error(:push_failed, msg_id: msg.msg_id, reason: :noproc)

# 仅开发 / IM_LOG_LEVEL=info 时输出；生产静默
IM.Log.info(:msg_send_ok, msg_id: msg.msg_id, duration_ms: duration)

# 仅开发 / IM_LOG_LEVEL=debug
IM.Log.debug(:packet_received, cmd: "CMD_MSG_SEND", payload_size: size)
```

**热路径（MSG_SEND 成功）**：只调 `IM.Telemetry`，**不**调 `IM.Log.info`。

### 3.2 高频采样 `IM.Log.RateLimit`

```elixir
defmodule IM.Log.RateLimit do
  @moduledoc false
  use GenServer

  @window_ms 60_000

  def allow?(bucket, fields) do
    key = {bucket, fields[:app_key], fields[:remote_ip] || fields[:user_id] || :global}
    GenServer.call(__MODULE__, {:allow?, key})
  end

  def handle_call({:allow?, key}, _from, state) do
    now = System.monotonic_time(:millisecond)

    case Map.get(state, key) do
      nil ->
        {:reply, true, Map.put(state, key, now)}

      last when now - last >= @window_ms ->
        {:reply, true, Map.put(state, key, now)}

      _ ->
        {:reply, false, state}
    end
  end
end
```

被采样丢弃时仍 `IM.Telemetry` 计数，告警靠指标而非日志条数。

### 3.3 `IM.Log.Metadata`

在 WebSocket / HTTP 请求入口设置 `Logger.metadata`，请求结束 `after` 块清理。

```elixir
defmodule IM.Log.Metadata do
  def set_from_packet(packet, socket) do
    trace_id = packet.trace_id |> nil_safe() |> ensure_trace_id()

    IM.Log.Metadata.put(%{
      trace_id: trace_id,
      app_key: socket.assigns[:app_key],
      user_id: socket.assigns[:user_id],
      device_id: socket.assigns[:device_id],
      cmd: IM.Protocol.Cmd.name(packet.cmd),
      seq: packet.seq,
      cid: packet.cid
    })

    trace_id
  end

  def put(kv), do: kv |> Enum.reject(fn {_, v} -> is_nil(v) end) |> Logger.metadata()
  def clear, do: Logger.metadata([])
end
```

### 3.4 Logger 配置

```elixir
# config/config.exs
config :im, :env, config_env()

# 开发：TTY 文本，但 metadata 键名与生产 JSON 一致（见 design/observability.md §2.6.0）
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: :all

# config/dev.exs
config :logger, level: :debug

# config/prod.exs — 仅 warning + error；单行 JSON（NDJSON）
config :logger, level: :warning

config :logger, :default_handler,
  formatter: {LoggerJSON.Formatters.Basic, metadata: :all}

config :logger_json, :backend,
  metadata: :all,
  json_encoder: Jason

# config/runtime.exs — 临时排障须审批；禁止长期 IM_LOG_LEVEL=info/debug
if level = System.get_env("IM_LOG_LEVEL") do
  config :logger, level: String.to_existing_atom(level)
end
```

生产使用 `LoggerJSON` 写 **stdout**（单行 JSON）；由 Promtail / Fluent Bit **异步**采集，应用进程不等待落盘。

**compile_time_purge_matching**（可选，进一步零成本剥离 debug）：

```elixir
# config/prod.exs
config :logger,
  compile_time_purge_matching: [
    [level_lower_than: :warning]
  ]
```

### 3.5 统一 JSON 信封（`IM.Log.Formatter`）

Formatter 在 `IM.Log` 写出前注入 §2.6.0 要求的 **信封字段**，保证全服务输出格式一致：

```elixir
defmodule IM.Log.Formatter do
  @moduledoc false

  @service "im"

  def envelope(metadata) do
    %{
      "@timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(:extended),
      "service" => @service,
      "host" => IM.Telemetry.host(),
      "node" => Node.self() |> Atom.to_string(),
      "event" => metadata[:event] && Atom.to_string(metadata[:event]),
      "message" => metadata[:event] && Atom.to_string(metadata[:event])
    }
    |> Map.merge(metadata_to_json(metadata))
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp metadata_to_json(metadata) do
    metadata
    |> Keyword.drop([:event])
    |> Enum.map(fn {k, v} -> {Atom.to_string(k), stringify(v)} end)
    |> Map.new()
  end

  defp stringify(v) when is_atom(v), do: Atom.to_string(v)
  defp stringify(v), do: v
end
```

在 `config/prod.exs` 中通过自定义 `LoggerJSON` formatter 或 `metadata` hook 合并 `envelope/1` 输出。验收标准：

| 检查项 | 期望 |
|--------|------|
| 单行 | 每条日志恰好一行，无嵌入换行 |
| `message` == `event` | 均为 event 原子字符串 |
| 信封齐全 | `@timestamp`, `level`, `service`, `host`, `node` 每条必有 |
| 调用点正确 | `caller_module` 为业务模块，非 `IM.Log` |
| 无自由文案 | grep 全库无 `Logger.info("`、`Logger.warning("`（除 `IM.Log` 与测试） |

**允许的 metadata 键**（白名单；新增须改设计文档 §2.6.2 并登记）：

```elixir
@metadata_keys ~w(
  event trace_id app_key user_id device_id cmd seq cid
  code ref_cmd reason msg_id client_msg_id duration_ms operation
  remote_ip caller_service channel_id namespace
  caller_module caller_file caller_line
)a
```

`config :logger, :default_formatter` / `LoggerJSON` 的 `metadata` 选项 **必须**包含上表键，否则字段会被静默丢弃。

**输出示例**（`IM.Log.warning(:packet_error, code: 2004, ref_cmd: :CMD_MSG_SEND)`，metadata 已设 `trace_id`）：

```json
{"@timestamp":"<ISO8601>","level":"warning","event":"packet_error","message":"packet_error","service":"im","host":"im-0","node":"im@10.0.0.12","trace_id":"abc","app_key":"demo","cmd":"CMD_MSG_SEND","code":2004,"ref_cmd":"CMD_MSG_SEND","caller_module":"Elixir.IM.Services.MessageSend","caller_file":"message_send.ex","caller_line":142}
```

---

## 4. 关键路径埋点示例

### 4.1 WebSocket 入口

```elixir
def handle_in({:binary, data}, socket) do
  case IM.Protocol.Codec.decode(data) do
    {:ok, packet} ->
      trace_id = IM.Log.Metadata.set_from_packet(packet, socket)
      IM.Telemetry.Packet.received(packet, socket, byte_size(data))

      try do
        # Router 选 Commands.*；Handler 内调 Application.Dispatch（业务 span 在 Service 层可选）
        IM.Protocol.Router.dispatch(packet, socket)
      rescue
        e ->
          IM.Log.error(:handler_crash,
            cmd: IM.Protocol.Cmd.name(packet.cmd),
            reason: Exception.message(e)
          )
          reraise e, __STACKTRACE__
      after
        IM.Log.Metadata.clear()
      end

    {:error, reason} ->
      IM.Log.error(:packet_decode_error,
        reason: inspect(reason),
        byte_size: byte_size(data)
      )
      {:noreply, socket}
  end
end
```

### 4.2 `CMD_ERROR` 统一记录

```elixir
defmodule IM.Protocol.Reply do
  def error(packet, %ErrorBody{code: code} = body) do
    IM.Log.warning(:packet_error,
      code: code,
      ref_cmd: body.ref_cmd,
      ref_cid: body.ref_cid,
      msg: body.msg
    )

    IM.Telemetry.packet_error(%{
      code: code,
      ref_cmd: body.ref_cmd,
      host: IM.Telemetry.Tags.host()
    })

    build_error_packet(packet, body)
  end
end
```

### 4.3 Handler debug 进出（仅开发）

```elixir
# 生产不调用；或 IM.Log.debug 在生产自动 no-op
if Logger.enabled?(:debug) do
  IM.Log.debug(:handler_exit, cmd: cmd, duration_ms: duration, result: result_tag(result))
end
```

### 4.4 高频命令采样（可选）

心跳等高频 cmd 的 debug 日志可采样，避免磁盘打满：

```elixir
def maybe_debug_packet(packet) do
  if packet.cmd == :CMD_HEARTBEAT_REQ and rem(packet.seq, 100) != 0 do
    :ok
  else
    IM.Log.debug(:packet_received, cmd: IM.Protocol.Cmd.name(packet.cmd), seq: packet.seq)
  end
end
```

---

## 5. 统一指标入口 `IM.Telemetry`

```elixir
defmodule IM.Telemetry do
  @prefix [:im]

  def packet_received(meta, measurements \\ %{count: 1}) do
    :telemetry.execute(@prefix ++ [:packet, :received], measurements, meta)
  end

  def packet_sent(meta, measurements \\ %{count: 1}) do
    :telemetry.execute(@prefix ++ [:packet, :sent], measurements, meta)
  end

  def packet_error(meta) do
    :telemetry.execute(@prefix ++ [:packet, :error], %{count: 1}, meta)
  end

  def ack_latency(stage, duration_ms, meta) do
    :telemetry.execute(
      @prefix ++ [:ack, :latency],
      %{duration: System.convert_time_unit(duration_ms, :millisecond, :native)},
      Map.put(meta, :stage, stage)
    )
  end
end
```

`cmd` 元数据统一用 atom 字符串名，由 `IM.Protocol.Cmd.name(packet.cmd)` 转换，避免魔法数字。

### 5.1 主机名与公共标签 `IM.Telemetry.Tags`

启动时缓存 `host`，避免热路径重复读环境变量。**指标 metadata 不含 `app_key`**（多租户高基数，仅进日志）；`trace_id` 亦不进 Telemetry，走 `Logger.metadata`。

```elixir
defmodule IM.Telemetry.Tags do
  @moduledoc false

  def host do
    Application.get_env(:im, :telemetry_host) ||
      System.get_env("HOSTNAME") ||
      case :inet.gethostname() do
        {:ok, name} -> to_string(name)
        _ -> "unknown"
      end
  end

  def node_name, do: node() |> Atom.to_string() |> String.split("@") |> List.last()

  # 仅含会导出为 Prometheus 标签的字段（低基数）
  def base(socket, packet) do
    %{
      cmd: IM.Protocol.Cmd.name(packet.cmd),
      host: host(),
      node: node_name(),
      msg_type: IM.Telemetry.MsgType.from_packet(packet)
    }
  end
end
```

`socket` 参数保留供后续扩展（如按连接状态区分），当前 **不** 将 `assigns` 中的 `app_key` 写入指标。

### 5.2 消息类型提取 `IM.Telemetry.MsgType`

```elixir
defmodule IM.Telemetry.MsgType do
  @moduledoc false

  @message_cmds ~w(CMD_MSG_SEND CMD_MSG_PUSH CMD_MSG_PUSH_BATCH CMD_MSG_EDIT_REQ)a

  def from_packet(%{cmd: cmd} = packet) when cmd in @message_cmds do
    case decode_msg_type(packet) do
      {:ok, type} -> type
      :error -> "unknown"
    end
  end

  def from_packet(_), do: "none"

  defp decode_msg_type(packet) do
    # 按 cmd 解码 payload，返回 MsgType 枚举名字符串，如 "MSG_TEXT"
    # 实现位于 IM.Protocol.Payload 或各 Commands 模块；解码失败返回 :error
    IM.Protocol.Payload.msg_type(packet)
  end
end
```

批量 `CMD_MSG_PUSH_BATCH`：首条 `msg_type`；若 batch 内类型不一致则 `mixed`。

`config/runtime.exs` 可注入 `config :im, :telemetry_host, System.get_env("HOSTNAME")`（K8s `fieldRef: metadata.name`）。

---

## 6. WebSocket 边界（上下行：计数 + 包大小）

在 Socket **收/发二进制帧**处记录 `byte_size`；`direction` 由事件类型隐含（`received`→`up`，`sent`→`down`），导出为 Prometheus 标签。

```elixir
defmodule IM.Telemetry.Packet do
  @moduledoc false

  def received(packet, socket, frame_size) when is_integer(frame_size) do
    meta =
      socket
      |> IM.Telemetry.Tags.base(packet)
      |> Map.put(:direction, "up")

    IM.Telemetry.packet_received(meta, %{count: 1, byte_size: frame_size})
  end

  def sent(packet, socket, frame_size) when is_integer(frame_size) do
    meta =
      socket
      |> IM.Telemetry.Tags.base(packet)
      |> Map.put(:direction, "down")

    IM.Telemetry.packet_sent(meta, %{count: 1, byte_size: frame_size})
  end
end
```

```elixir
defmodule IMWeb.UserSocket do
  def handle_in({:binary, data}, socket) do
    frame_size = byte_size(data)

    with {:ok, packet} <- IM.Protocol.Codec.decode(data) do
      IM.Telemetry.Packet.received(packet, socket, frame_size)
      # ... route to handler
    end
  end

  def push(socket, packet) do
    {:ok, encoded} = IM.Protocol.Codec.encode(packet)
    IM.Telemetry.Packet.sent(packet, socket, byte_size(encoded))
    push(socket, {:binary, encoded})
  end
end
```

---

## 6. WebSocket 边界（上下行：计数 + 包大小）

`IM.Protocol.Router` 的 span 覆盖 **协议层**（选 Handler + 回调）；metadata 须含 `host`、`msg_type`、`direction`，与包大小指标标签对齐。

```elixir
defmodule IM.Protocol.Router do
  def dispatch(packet, socket) do
    meta =
      socket
      |> IM.Telemetry.Tags.base(packet)
      |> Map.put(:direction, "up")
      |> Map.put(:result, :ok)

    :telemetry.span([:im, :handler], meta, fn ->
      case do_dispatch(packet, socket) do
        {:ok, reply, socket} ->
          {reply, meta}

        {:error, reason, socket} ->
          {{:error, reason}, Map.put(meta, :result, :error)}
      end
    end)
  end
end
```

`Telemetry.Metrics` 将 `[:im, :handler, :stop]` 的 `duration` 转为 `im_handler_duration_ms` histogram（标签：`cmd`, `result`, `host`, `msg_type`, `direction`；**无 `app_key`**）。

## 8. ACK 延迟跟踪

进程内 ETS 表 `IM.Telemetry.Ack`（`:bag` 或 `:set`），key = `{app_key, client_msg_id}` 或 `msg_id`：

```elixir
defmodule IM.Telemetry.Ack do
  @table :im_ack_timers

  def on_msg_send(packet, ctx) do
    key = {ctx.app_key, client_msg_id_from(packet)}
    t0 = System.monotonic_time(:millisecond)

    :ets.insert(@table, {key, :send_received_at, t0})
    # 缓存 ack 指标标签（不含 app_key）
    :ets.insert(@table, {key, :ack_meta, %{
      host: IM.Telemetry.Tags.host(),
      msg_type: IM.Telemetry.MsgType.from_packet(packet),
      chat_type: ctx.chat_type
    }})
    :ok
  end

  def on_server_ack(key, meta) do
    ack_meta = Map.merge(lookup_ack_meta(key), meta)

    case :ets.lookup(@table, {key, :send_received_at}) do
      [{_, _, t0}] ->
        duration = System.monotonic_time(:millisecond) - t0
        IM.Telemetry.ack_latency(:send_to_server_ack, duration, ack_meta)
        :ets.insert(@table, {key, :server_ack_at, System.monotonic_time(:millisecond)})
      _ -> :ok
    end
  end

  def on_push_delivered(key, meta) do
    # send_to_push：从 send_received_at 到此刻
  end

  def on_client_ack(key, meta) do
    # send_to_client_ack
    :ets.delete(@table, key)
  end
end
```

ETS 条目 TTL 5min 自动清理（`:telemetry_poller` 周期扫），防止泄漏。

---

## 9. Delivery 扇出

```elixir
defmodule IM.Delivery.Router do
  def deliver(message, recipients, opts) do
    meta = %{
      chat_type: message.chat_type,
      fanout_mode: fanout_mode(recipients),
      host: IM.Telemetry.Tags.host(),
      msg_type: message.msg_type |> Atom.to_string()
    }

    :telemetry.span([:im, :delivery], meta, fn ->
      {count, _} = do_deliver(message, recipients, opts)
      {{:ok, count}, Map.put(meta, :recipients, count)}
    end)
  end
end
```

跨节点推送时额外 `IM.Telemetry.execute([:im, :cluster, :dispatch], %{count: 1}, %{target_node: node})`。

---

## 10. Metrics 定义（Prometheus）

```elixir
defmodule IM.Telemetry.Metrics do
  import Telemetry.Metrics

  @packet_tags [:cmd, :host, :msg_type, :direction, :node]
  @byte_buckets [256, 512, 1024, 2048, 4096, 8192, 16_384, 32_768, 65_536]
  @duration_buckets [5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000]

  def metrics do
    [
      counter("im.packet.received.total",
        event_name: [:im, :packet, :received],
        tags: @packet_tags
      ),
      counter("im.packet.sent.total",
        event_name: [:im, :packet, :sent],
        tags: @packet_tags
      ),
      distribution("im.packet.received.bytes",
        event_name: [:im, :packet, :received],
        measurement: :byte_size,
        unit: :byte,
        tags: @packet_tags,
        reporter_options: [buckets: @byte_buckets]
      ),
      distribution("im.packet.sent.bytes",
        event_name: [:im, :packet, :sent],
        measurement: :byte_size,
        unit: :byte,
        tags: @packet_tags,
        reporter_options: [buckets: @byte_buckets]
      ),
      counter("im.packet.errors.total",
        event_name: [:im, :packet, :error],
        tags: [:code, :ref_cmd, :host]
      ),
      distribution("im.handler.duration.ms",
        event_name: [:im, :handler, :stop],
        unit: {:native, :millisecond},
        tags: [:cmd, :result, :host, :msg_type, :direction],
        reporter_options: [buckets: @duration_buckets]
      ),
      distribution("im.ack.latency.ms",
        event_name: [:im, :ack, :latency],
        unit: {:native, :millisecond},
        tags: [:stage, :chat_type, :host, :msg_type],
        reporter_options: [buckets: @duration_buckets]
      ),
      distribution("im.delivery.duration.ms",
        event_name: [:im, :delivery, :stop],
        unit: {:native, :millisecond},
        tags: [:chat_type, :fanout_mode, :host, :msg_type]
      ),
      last_value("im.connections.active",
        event_name: [:im, :connection, :stats],
        measurement: :active,
        tags: [:host, :node]
      )
    ]
  end
end
```

Phase 9 在 Endpoint 暴露 `GET /metrics`（仅内网或 ServiceMonitor 抓取）。

---

## 11. 连接 Gauge

```elixir
defmodule IM.Telemetry.Connection do
  use GenServer
  # 维护 active 计数；connect +1、disconnect -1、auth 记 im_auth_total
  # :telemetry_poller 每 10s execute [:im, :connection, :stats], %{active: n}, %{node: node}
end
```

或与 `IM.Connection.Registry` 联动，poller 回调读 Registry 当前数量。

---

## 12. 测试

```elixir
test "MSG_SEND records upstream byte_size and tags" do
  handler = fn event, measurements, metadata, _ ->
    send(self(), {event, measurements, metadata})
  end

  :telemetry.attach("test", [:im, :packet, :received], handler, nil)

  simulate_packet(%Packet{cmd: :CMD_MSG_SEND}, frame_size: 512)

  assert_receive {[:im, :packet, :received], %{count: 1, byte_size: 512},
                  %{
                    cmd: "CMD_MSG_SEND",
                    direction: "up",
                    host: host,
                    msg_type: "MSG_TEXT"
                  }}
                 when is_binary(host)
end

test "handler span includes duration and host" do
  :telemetry.attach("test-span", [:im, :handler, :stop], fn _e, m, meta, _ ->
    send(self(), {:handler_stop, m, meta})
  end, nil)

  dispatch_msg_send(...)

  assert_receive {:handler_stop, %{duration: d}, %{host: host, msg_type: type, direction: "up"}}
                 when d > 0 and is_binary(host)
end
```

ACK 延迟集成测试：发 SEND → 断言 `send_to_server_ack` 事件 `duration < 100ms`（本地）。

---

## 13. 验收要点

| Phase | 验收 |
|-------|------|
| P2-08 | 上下行 counter + **包大小 histogram**（`byte_size`）；标签含 **`host`、`msg_type`、`direction`**；`im_handler_duration_ms` 含 `host`/`msg_type`；`im_connections_active` 按 `host` |
| P2-09 | 生产 `level: :warning`；仅白名单 event；`auth_failed` 采样；MSG_SEND 成功无日志 |
| P3-10 | 单聊 SEND 全链路产生 `send_to_server_ack`、`send_to_push` histogram（标签含 `host`、`msg_type`） |
| P9-05 | `/metrics` 可 scrape；日志 JSON 输出；Grafana 可按 `host` / `msg_type` / `cmd` 切片 |

---

## 14. 看板与日志查询

| 面板 | PromQL 思路 |
|------|-------------|
| 上行 QPS by cmd | `sum by (cmd) (rate(im_packet_received_total[1m]))` |
| 下行 QPS by cmd | `sum by (cmd) (rate(im_packet_sent_total[1m]))` |
| 上行包大小 P99 | `histogram_quantile(0.99, sum by (le, cmd) (rate(im_packet_received_bytes_bucket[5m])))` |
| 按 host 流量 | `sum by (host) (rate(im_packet_received_total[1m]))` |
| 按 msg_type 延迟 | `histogram_quantile(0.99, sum by (le, msg_type) (rate(im_handler_duration_ms_bucket{direction="up"}[5m])))` |
| 主路径 P99 | `histogram_quantile(0.99, im_ack_latency_ms_bucket{stage="send_to_server_ack"})` |
| 错误率 | `rate(im_packet_errors_total[5m]) / rate(im_packet_received_total[5m])` |
| 在线连接 by host | `im_connections_active` |

### Loki / ELK 查询示例

```text
{app="im"} | json | event="msg_send_failed"
{app="im"} | json | trace_id="abc123"
{app="im"} | json | level="error"
{app="im"} | json | event="auth_failed" | app_key="my_app"
{app="im"} | json | caller_module="Elixir.IM.Services.MessageSend"
```
