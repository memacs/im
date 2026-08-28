# Kafka 事件总线 - Elixir 实现

| 项 | 内容 |
|------|------|
| 语言 | Elixir |
| 设计文档 | [kafka-event-bus.md](../../design/kafka-event-bus.md) |
| Roadmap | Phase 9（P9-03、P9-03b、P9-03c） |

---

## 1. 模块结构

```
lib/im/event_bus/
  ├── behaviour.ex          # IM.EventBus behaviour（publish）
  ├── kafka_producer.ex     # Broadway / brod / kafka_ex 实现
  ├── buffer.ex             # GenServer 异步队列 + 批量发送
  ├── encoder.ex            # Protobuf 编码（默认）/ JSON（开发）
  ├── upstream.ex           # 上行事件构造
  ├── downstream.ex         # 下行事件构造 + fanout 减量
  ├── session.ex            # login/logout/heartbeat
  ├── push.ex               # PushNotificationBatchEvent → im.push
  └── fanout_policy.ex      # direct / aggregated 判定
```

对外唯一 API：`IM.EventBus.publish(topic, event, opts)`。

---

## 2. Behaviour

```elixir
defmodule IM.EventBus do
  @callback publish(atom(), map(), keyword()) :: :ok

  def publish(topic, event, opts \\ []) do
    impl().publish(topic, event, opts)
  end

  defp impl, do: Application.get_env(:im, :event_bus, IM.EventBus.Kafka)
end
```

测试环境配置 `IM.EventBus.Mock`（断言事件而不连 Kafka）。

---

## 3. 配置

```elixir
# config/config.exs
config :im, :event_bus, IM.EventBus.Kafka

config :im, IM.EventBus.Kafka,
  enabled: true,
  brokers: [{"kafka", 9092}],
  topics: %{
    upstream: "im.upstream",
    session: "im.session",
    downstream: "im.downstream",
    push: "im.push",
    dlq: "im.dlq"
  },
  push_enabled: true,
  push_room_enabled: false,
  upstream_on: :accepted,
  session_heartbeat_mode: :sampled,
  session_heartbeat_sample_rate: 0.01,
  session_heartbeat_min_interval_ms: 300_000,
  downstream_fanout_direct_max: 100,
  downstream_group_large_threshold: 500,
  downstream_room_mode: :aggregated,
  downstream_room_recipient_list_max: 2000,
  downstream_group_recipient_list_max: 500,
  buffer_max_len: 10_000,
  batch_size: 100,
  batch_timeout_ms: 50,
  serialization: :protobuf,        # 生产默认
  kafka_record_headers: true         # 索引见 Headers §2.10.6；开发可用 :json_envelope
```

```elixir
# config/test.exs
config :im, :event_bus, IM.EventBus.Mock
config :im, IM.EventBus.Kafka, enabled: false
```

---

## 4. 序列化：PB 信封 + Headers 索引

设计见 [kafka-event-bus.md](../../design/kafka-event-bus.md) §2.10.6。

| 模式 | 说明 |
|------|------|
| `:protobuf` + headers | **生产默认**；value 为 `UpstreamEvent` bytes；索引在 Kafka Headers |
| `:json_envelope` | 仅开发；小 JSON + `payload` base64，比纯 PB 更慢 |

**「JSON 几个重要字段 + PB 完整体」**：用 **Headers（索引）+ PB value（meta + bytes payload）** 实现，不要用 JSON 包 base64(payload)。

消费方只过滤时读 Headers；需要正文再 decode `UpstreamEvent`，**仅按需** decode 内层 `payload` proto。

```elixir
# value：UpstreamEvent.encode；payload = packet.raw_payload
# headers：x-im-app-key, x-im-cmd, x-im-trace-id, …
```

---

## 5. 异步 Buffer（不阻塞主路径）

```elixir
defmodule IM.EventBus.Buffer do
  use GenServer

  def cast(topic, event, partition_key) do
    GenServer.cast(__MODULE__, {:enqueue, topic, event, partition_key})
  end

  def handle_cast({:enqueue, topic, event, key}, state) do
    if length(state.queue) >= state.max_len do
      :telemetry.execute([:im, :eventbus, :dropped], %{count: 1}, %{topic: topic})
      {:noreply, state}
    else
      {:noreply, %{state | queue: [{topic, event, key} | state.queue]}}
    end
  end

  # batch_timeout / batch_size 触发 flush → KafkaProducer.produce_batch/1
end
```

**`CMD_MSG_SEND` 路径**：`EventBus.cast` 后立即继续 ACK，**绝不** `GenServer.call`。

---

## 6. 上行写入点

| 入口 | 模块 | 调用 |
|------|------|------|
| WebSocket | `IM.Protocol.Router` → `Commands.*`（业务经 `Dispatch`） | `Upstream.publish(packet, ctx)` |
| HTTP REST | `IMWeb.Api.*Controller`（经 `Dispatch`） | `Upstream.publish_from_http(conn, cmd, body)` |

```elixir
defmodule IM.EventBus.Upstream do
  def publish(packet, ctx) do
    if ctx.write_kafka do
      event = %{
        event_id: UUID.uuid4(),
        event_type: "upstream",
        timestamp: System.system_time(:millisecond),
        app_key: ctx.app_key,
        trace_id: ctx.trace_id,
        source: to_string(ctx.source),
        ingress: ingress(ctx),
        cmd: IM.Protocol.Cmd.name(packet.cmd),
        user_id: ctx.user_id,
        device_id: ctx.device_id,
        route_key: packet.route_key,
        # Packet 已解码，但保留原始 payload 字节用于 Kafka（在 Codec 层缓存 raw_payload）
        payload: packet.raw_payload
      }

      key = "#{ctx.app_key}:#{ctx.user_id}"
      IM.EventBus.Buffer.cast(:upstream, event, key)
    end

    :ok
  end
end
```

`upstream_on: :accepted` 时在 Handler **成功返回后** 调用，而非收包瞬间。

---

## 7. 会话写入点

```elixir
defmodule IM.EventBus.Session do
  def login(ctx) do
    publish(:session, "login", ctx, %{session_id: ctx.session_id, platform: ctx.platform})
  end

  def logout(ctx, reason) do
    publish(:session, "logout", ctx, %{reason: reason})
  end

  def heartbeat(ctx) do
    if heartbeat_allowed?(ctx) do
      publish(:session, "heartbeat", ctx, %{})
    end

    :ok
  end

  defp heartbeat_allowed?(ctx) do
    case Application.get_env(:im, IM.EventBus.Kafka)[:session_heartbeat_mode] do
      :off -> false
      :all -> true
      :sampled -> sampled?(ctx)
    end
  end
end
```

调用位置：

| 事件 | 位置 |
|------|------|
| `login` | `IM.WebSocket.Commands.Auth` 成功后 |
| `logout` | `UserSocket.terminate/2`、`CMD_KICK`、进程 DOWN |
| `heartbeat` | `IM.WebSocket.Commands.Heartbeat` 成功后 |

---

## 7. 下行写入与减量

扇出**结束后**写 **1 条** `im.downstream`。聊天室在 `fanout.audience` 中带 **from + recipient_user_ids**（用户级，非每设备一条）。

```elixir
defmodule IM.EventBus.Downstream do
  def publish_push(message, packet, targets, ctx) do
    if ctx.write_kafka do
      {mode, target_users} = FanoutPolicy.resolve(message, targets)
      audience = build_audience(message, targets, mode, ctx)

      event = %{
        fanout: %{
          mode: mode,
          recipient_count: length(targets),
          online_count: audience.online_count,
          target_users: target_users,
          audience: audience
        },
        targets: if(mode == :direct, do: slim_targets(targets), else: []),
        payload: packet.raw_payload
      }

      IM.EventBus.Buffer.cast(:downstream, event, "#{ctx.app_key}:#{message.msg_id}")
    end

    :ok
  end
end
```

```elixir
defmodule IM.EventBus.Audience do
  @doc """
  从扇出 targets 提取 user_id 列表（已排除发送设备对应用户重复设备）。
  聊天室/大群：一条 Kafka 内带 recipient_user_ids，超上限则 truncate。
  """
  def build(message, targets, mode, ctx) do
    user_ids =
      targets
      |> Enum.map(& &1.user_id)
      |> Enum.uniq()
      |> List.delete(message.from)  # 发送方设备已排除，用户级可保留或按产品定

    max = recipient_list_max(mode, message.chat_type)
    {list, truncated?} = truncate(user_ids, max)

    %{
      from_user_id: message.from,
      from_device_id: ctx.device_id,
      recipient_user_ids: list,
      recipient_list_truncated: truncated?,
      recipient_list_max: max,
      online_count: length(user_ids)
    }
  end

  defp recipient_list_max(:room_aggregated, _), do: config!(:downstream_room_recipient_list_max)
  defp recipient_list_max(:group_aggregated, _), do: config!(:downstream_group_recipient_list_max)
  defp recipient_list_max(_, _), do: :infinity
end
```

**注意**：`recipient_user_ids` 是本次**实际推送到的在线用户**；发送方其它设备若在 targets 中则会出现。发送设备本身不出现（协议已排除）。

```elixir
defmodule IM.EventBus.FanoutPolicy do
  def resolve(%{chat_type: :CHAT_PRIVATE}, targets), do: {:direct, nil}

  def resolve(%{chat_type: :CHAT_GROUP, to: group_id}, targets) do
    threshold = config!(:downstream_group_large_threshold)
    member_count = IM.Stores.GroupStore.member_count(group_id)

    if member_count > threshold do
      {:group_aggregated, nil}
    else
      {:direct, nil}
    end
  end

  def resolve(%{chat_type: :CHAT_ROOM}, _targets) do
    {config!(:downstream_room_mode), nil}
  end
end
```

`CMD_MSG_PUSH_BATCH`：整批 **1 条** Kafka，`payload` 含 `messages: [...]`。

---

## 8. Kafka Producer

```elixir
defmodule IM.EventBus.Kafka do
  @behaviour IM.EventBus

  def publish(topic_key, event, opts) do
    if enabled?() do
      topic = topics()[topic_key]
      key = Keyword.get(opts, :partition_key, event[:event_id])
      IM.EventBus.Buffer.cast(topic_key, event, key)
    end

    :ok
  end
end
```

底层可用 `brod` / `kafka_protocol`；批量 `produce` 由 Buffer flush 触发。

失败重试 N 次后：

```elixir
IM.EventBus.DLQ.push(original_topic, event, reason)
:telemetry.execute([:im, :eventbus, :publish], %{count: 1}, %{topic: topic, result: :error})
```

---

## 9. 防循环

```elixir
# Kafka 消费入口构造 Context
IM.Domain.MessageContext.from_kafka(msg)
# => %{source: :kafka, write_kafka: false, ...}
```

HTTP 内部回调若回灌 IM，显式 `write_kafka: false`。

---

## 10. 验收要点

| 项 | 验收 |
|----|------|
| WS `MSG_SEND` | `im.upstream` 有 1 条；主路径 P99 不因 Kafka 劣化 >1% |
| AUTH 成功 | `im.session` login 1 条 |
| 断连 | `im.session` logout 1 条 |
| 单聊 PUSH | `im.downstream` direct |
| 5000 人群 PUSH | `im.downstream` **1 条** aggregated + `audience.recipient_user_ids`（≤500，可 truncated） |
| 聊天室广播 | **1 条**；`from_user_id` + `recipient_user_ids`（≤2000） |
| 单聊对端 1 台离线 + token | `im.push` **1 条** batch，`targets` 长度 1 |
| 群 2 台离线设备 | `im.push` **1 条** batch，`targets` 长度 2 |
| Kafka 宕机 | IM 收发正常；`eventbus_dropped` 或 DLQ 有记录 |
| REST 发消息 | 与 WS 相同写入 `im.upstream` |

---

## 11. 本地开发

```yaml
# deploy/elixir/im/k8s/base/deps/kafka.yaml（Phase 9 添加）
# mise run k8s-up 可选包含 Kafka
```

单测使用 `IM.EventBus.Mock`；集成测试可选 Testcontainers Kafka。
