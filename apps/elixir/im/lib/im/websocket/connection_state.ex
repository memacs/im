defmodule IM.WebSocket.ConnectionState do
  @moduledoc """
  单条 WS 连接的进程内状态：鉴权态、会话标识、心跳时间戳、协商的压缩算法。

  鉴权前只允许 `CMD_AUTH_REQ`，门禁由 `IM.Protocol.Router` 依据本结构的 `authenticated?` 判定。

  P0-05 骨架：字段随 P1 鉴权与心跳实现补齐。
  """

  defstruct authenticated?: false,
            context: nil,
            last_heartbeat_at: nil,
            compression: :none

  @type t :: %__MODULE__{
          authenticated?: boolean(),
          context: IM.Domain.MessageContext.t() | nil,
          last_heartbeat_at: integer() | nil,
          compression: atom()
        }
end
