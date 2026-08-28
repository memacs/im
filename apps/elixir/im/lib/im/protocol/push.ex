defmodule IM.Protocol.Push do
  @moduledoc """
  构造服务端主动下推的 `Packet`。推送包 `seq = 0`（`seq` 只用于客户端请求-响应匹配），
  `trace_id` 继承触发它的根请求。

  P0-05 骨架：随 `IM.Delivery.Router` 在 Phase 3 一起落地。
  """

  alias IM.Domain.Error

  @doc """
  构造推送包。`cmd` 为 `CMD_MSG_PUSH` 等推送类命令字。
  """
  @spec build(non_neg_integer(), term(), keyword()) :: {:ok, struct()} | {:error, Error.t()}
  def build(cmd, _payload, _opts \\ []) when is_integer(cmd) do
    {:error, Error.not_implemented(cmd)}
  end
end
