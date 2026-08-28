defmodule IM.Hooks.Behaviour do
  @moduledoc """
  Pre-send Hook 契约（P9-04）。

  同步执行；可改写消息或拦截发送。
  """

  alias IM.Domain.{Error, MessageContext}
  alias Pb.Im.Protocol.ChatMessage

  @type result ::
          :ok
          | {:ok, ChatMessage.t()}
          | {:error, Error.t() | atom() | String.t()}
          | {:reject, term()}

  @doc "发送前同步 Hook。"
  @callback pre_send(ChatMessage.t(), MessageContext.t()) :: result()
end
