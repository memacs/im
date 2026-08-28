defmodule IM.Delivery.Router do
  @moduledoc """
  下行扇出：Service 产出消息后，决定投递到本节点 WS 连接、跨节点转发、还是转移动端推送。

  与 `IM.Application.Dispatch`（上行分发）方向相反、职责无交集，两者不要互相调用。

  P0-05 骨架：随 Phase 3 的在线投递与 Phase 6 的离线推送落地。
  """

  alias IM.Domain.{Error, MessageContext}

  @doc """
  投递一条下行消息给目标接收方。
  """
  @spec deliver(map() | struct(), MessageContext.t() | map()) :: :ok | {:error, Error.t()}
  def deliver(message, _ctx) when is_map(message) do
    {:error, Error.not_implemented()}
  end
end
