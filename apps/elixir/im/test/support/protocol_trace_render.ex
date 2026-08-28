defmodule IM.ProtocolTraceRender do
  @moduledoc false

  @packet_fields %{
    "ver" => "协议版本，当前固定 1",
    "cmd" => "命令字（CmdType 枚举整数值）",
    "cmd_name" => "命令字名称（文档衍生字段）",
    "seq" => "请求序号；客户端上行单调递增；服务端推送为 0",
    "ts" => "发送时间戳（毫秒）",
    "cid" => "请求级幂等 ID；PUSH 时可能携带 client_msg_id",
    "trace_id" => "链路追踪 ID",
    "route_key" => "网关分流键；单聊常为 conv_id，群/室为 group_id/room_id",
    "compression" => "payload 压缩算法"
  }

  @field_docs %{
    "app_key" => "租户应用标识",
    "user_id" => "业务用户 ID",
    "device_id" => "设备唯一标识",
    "platform" => "客户端平台：ios/android/web/desktop",
    "sdk_ver" => "SDK 版本号",
    "access_token" => "REST 返回的会话 token",
    "expires_at" => "token 过期时间（毫秒时间戳）",
    "token" => "WS 鉴权 token（与 REST access_token 相同）",
    "client_time" => "客户端本地时间（毫秒）",
    "server_time" => "服务端当前时间（毫秒）",
    "session_id" => "WS 会话 ID",
    "heartbeat_interval_sec" => "心跳间隔（秒）",
    "client_msg_id" => "消息级幂等 ID（业务去重）",
    "msg_id" => "服务端分配的全局消息 ID（雪花）",
    "conv_id" => "会话 ID；单聊 p:{lo}:{hi} 字典序",
    "conv_seq" => "会话内单调排序位点",
    "status" => "ACK 状态：ACK_SERVER_RECEIVED / ACK_CLIENT_RECEIVED",
    "code" => "ErrorCode 枚举值",
    "ref_cmd" => "引发错误的原始请求 cmd",
    "msg" => "人类可读错误说明",
    "from" => "发送方 user_id",
    "to" => "接收目标：单聊=对端 uid；群=group_id；室=room_id",
    "chat_type" => "会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM",
    "msg_type" => "消息内容类型：MSG_TEXT/MSG_STREAM 等",
    "content" => "消息体；MSG_TEXT 为 UTF-8 文本；MSG_STREAM 为 StreamContent 结构",
    "reason" => "踢下线/撤回等原因",
    "reason_code" => "KickReason 枚举",
    "request_id" => "好友请求 ID",
    "group_id" => "群 ID",
    "room_id" => "聊天室 ID",
    "channel_id" => "应用通道 ID（namespace:name）",
    "stream_id" => "流式消息 ID",
    "sequence" => "流式分块序号",
    "chunk" => "流式分块内容",
    "action" => "透传 action 名",
    "data" => "透传 JSON 字符串",
    "cursor" => "离线拉取游标（conv_seq）",
    "limit" => "离线拉取条数上限",
    "event" => "非 WS 报文事件类型",
    "detail" => "事件补充说明"
  }

  def write!(path, traces) when is_list(traces) do
    content = render(traces)
    File.write!(path, content)
    path
  end

  defp render(traces) do
    cases = traces |> Enum.group_by(& &1["case"]) |> Enum.sort_by(fn {k, _} -> k end)

    index =
      cases
      |> Enum.with_index(1)
      |> Enum.map(fn {{case_id, _}, idx} ->
        anchor = case_anchor(case_id)
        "#{idx}. [#{case_id}](#{anchor})"
      end)
      |> Enum.join("\n")

    body =
      cases
      |> Enum.map(fn {case_id, steps} ->
        sorted = Enum.sort_by(steps, & &1["step"])
        render_case(case_id, sorted)
      end)
      |> Enum.join("\n\n---\n\n")

    """
    # 协议 E2E 消息时序与字段详解（im_client）

    | 项 | 内容 |
    | --- | --- |
    | 测试目录 | `apps/elixir/im/test/im_client/protocol/` |
    | **实测报文 JSON** | [`protocol-e2e-traces.json`](protocol-e2e-traces.json)（`TRACE_EXPORT=1 mix test.trace` 自动生成） |
    | 重新生成 | `PGPORT=15432 TRACE_EXPORT=1 CLUSTER_E2E=1 mix test.trace` |
    | 协议权威 | [`proto/`](../../../proto/) + [`protocol.md`](../../design/protocol/protocol.md) |

    本文每个用例的 **字段值均来自 E2E trace 导出**（与 `test/im_client/protocol/*_test.exs` 同步）。
    `msg_id`/`session_id`/`access_token` 等每次运行会变，但 **字段结构与相对关系** 与线上一致。

    > **维护约定**：新增或修改 protocol E2E 用例时，须添加 `@tag trace_case` 并在关键步骤调用 `trace!/2`；
    > 提交前运行 `mix test.trace` 更新本文与 JSON。`trace_coverage_test.exs` 会校验用例清单完整。

    ---

    ## 1. Packet 信封字段（所有 WS 帧共有）

    | 字段 | 类型 | 说明 |
    | --- | --- | --- |
    | `ver` | uint32 | 协议版本，当前 = 1 |
    | `cmd` | uint32 | 命令字，见 CmdType |
    | `seq` | uint64 | 客户端请求序号；**推送包 = 0** |
    | `ts` | int64 | 发送时间戳（ms） |
    | `cid` | string | 请求级幂等；与 `client_msg_id` 职责分离 |
    | `trace_id` | string | 链路追踪 ID |
    | `route_key` | string | 网关/集群分流键 |
    | `compression` | enum | payload 压缩；鉴权后多为 NONE |
    | `payload` | bytes | Protobuf 业务体 |

    ---

    ## 用例索引（E2E 实测 trace）

    #{index}

    ---

    #{body}
    """
  end

  defp render_case(case_id, steps) do
    header = "## #{case_id}\n"

    steps_body =
      steps
      |> Enum.map(&render_step/1)
      |> Enum.join("\n\n")

    header <> steps_body
  end

  defp render_step(%{"step" => step, "actor" => actor, "direction" => direction} = entry) do
    title = "### 步骤 #{step}：#{direction}（#{actor}）"

    sections =
      cond do
        Map.has_key?(entry, "http") ->
          [render_http(entry["http"])]

        Map.has_key?(entry, "packet") ->
          [render_packet(entry["packet"])]

        Map.has_key?(entry, "event") ->
          [render_event(entry["event"])]

        true ->
          []
      end

    json_block =
      "<details><summary>完整 JSON</summary>\n\n```json\n#{Jason.encode!(entry, pretty: true)}\n```\n\n</details>"

    ([title | sections] ++ [json_block]) |> Enum.join("\n\n")
  end

  defp render_packet(packet) do
    envelope =
      packet
      |> Map.take([
        "ver",
        "cmd",
        "cmd_name",
        "seq",
        "ts",
        "cid",
        "trace_id",
        "route_key",
        "compression"
      ])
      |> Map.new(fn {k, v} -> {k, format_value(v)} end)

    envelope_table =
      "**Packet 信封**\n\n" <> render_table(envelope, @packet_fields)

    payload = Map.get(packet, "payload")

    payload_table =
      if payload && payload != %{} do
        flat = flatten_map(payload)
        "\n\n**payload 字段**\n\n" <> render_table(flat, @field_docs)
      else
        ""
      end

    envelope_table <> payload_table
  end

  defp render_http(%{"request" => req, "response" => resp}) do
    req_table =
      if is_map(req) do
        "**HTTP 请求体**\n\n" <> render_table(flatten_map(req), @field_docs)
      else
        ""
      end

    resp_body = get_in(resp, ["body"]) || resp

    resp_table =
      if is_map(resp_body) do
        flat =
          resp_body
          |> flatten_map()
          |> Enum.take(12)
          |> Map.new()

        "\n\n**HTTP 响应体（节选）**\n\n" <> render_table(flat, @field_docs)
      else
        ""
      end

    req_table <> resp_table
  end

  defp render_event(event) when is_map(event) do
    "**事件（无 WS 报文）**\n\n" <> render_table(flatten_map(event), @field_docs)
  end

  defp render_table(fields, docs) when is_map(fields) do
    rows =
      fields
      |> Enum.sort_by(fn {k, _} -> k end)
      |> Enum.map(fn {field, value} ->
        doc = Map.get(docs, field) || nested_doc(field, docs) || ""
        "| `#{field}` | `#{escape_cell(value)}` | #{doc} |"
      end)

    ["| 字段 | E2E 实测值 | 说明 |", "| --- | --- | --- |" | rows]
    |> Enum.join("\n")
  end

  defp nested_doc(field, docs) do
    case String.split(field, ".", parts: 2) do
      [_prefix, leaf] -> Map.get(docs, leaf)
      _ -> nil
    end
  end

  defp flatten_map(map, prefix \\ "") do
    Enum.reduce(map, %{}, fn {k, v}, acc ->
      key = if prefix == "", do: to_string(k), else: prefix <> "." <> to_string(k)

      cond do
        is_map(v) && map_size(v) > 0 && not struct_like?(v) ->
          Map.merge(acc, flatten_map(v, key))

        is_list(v) ->
          Map.put(acc, key, format_value(v))

        true ->
          Map.put(acc, key, format_value(v))
      end
    end)
  end

  defp struct_like?(%{} = map) do
    Enum.all?(map, fn {k, _} -> is_binary(k) end)
  end

  defp format_value(v) when is_binary(v) do
    if String.length(v) > 48, do: String.slice(v, 0, 12) <> "…", else: v
  end

  defp format_value(v) when is_list(v), do: Jason.encode!(normalize_json(v))
  defp format_value(v) when is_map(v), do: Jason.encode!(normalize_json(v))
  defp format_value(nil), do: ""
  defp format_value(v) when is_atom(v), do: Atom.to_string(v)
  defp format_value(v), do: inspect(v)

  defp normalize_json(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), normalize_json(v)} end)
  end

  defp normalize_json(list) when is_list(list), do: Enum.map(list, &normalize_json/1)
  defp normalize_json(%_{} = s), do: s |> Map.from_struct() |> normalize_json()
  defp normalize_json(other), do: other

  defp escape_cell(value) when is_binary(value), do: String.replace(value, "|", "\\|")
  defp escape_cell(value), do: value |> to_string() |> escape_cell()

  defp case_anchor(case_id) do
    "#" <> URI.encode(case_id)
  end
end
