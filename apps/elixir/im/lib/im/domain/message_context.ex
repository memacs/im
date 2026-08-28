defmodule IM.Domain.MessageContext do
  @moduledoc """
  一次请求的身份与链路上下文，贯穿 WS、REST、Kafka 三条入站路径。

  字段定义与传播规则见仓库根 `docs/implementation/elixir/message-context.md`。
  `trace_id` 由根请求入站时确定，衍生的 ACK / PUSH / ERROR 必须继承同一值。

  P0-05 骨架：结构已定型，`from_socket/2`、`from_conn/1` 等构造函数在 Phase 1 落地。
  """

  @enforce_keys [:app_key, :user_id, :device_id, :trace_id]

  defstruct [
    :app_key,
    :user_id,
    :device_id,
    :session_id,
    :platform,
    :trace_id,
    :node,
    :connected_at
  ]

  @type t :: %__MODULE__{
          app_key: String.t(),
          user_id: String.t(),
          device_id: String.t(),
          session_id: String.t() | nil,
          platform: atom() | nil,
          trace_id: String.t(),
          node: node() | nil,
          connected_at: DateTime.t() | nil
        }
end
