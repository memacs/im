defmodule IM.Hooks.PreSend do
  @moduledoc """
  发消息同步 Pre-Hook 门面（P3-08 / P9-04）。

  委托 `IM.Hooks.Pipeline`；兼容旧配置 `:pre_send_hook`。
  """

  alias IM.Domain.{Error, MessageContext}
  alias IM.Hooks.Pipeline
  alias Pb.Im.Protocol.ChatMessage

  @doc """
  执行 pre_send 链，返回可能被改写的消息。

  ## 示例

      {:ok, msg} = IM.Hooks.PreSend.run(msg, ctx)
  """
  @spec run(ChatMessage.t(), MessageContext.t()) ::
          {:ok, ChatMessage.t()} | {:error, Error.t()}
  def run(%ChatMessage{} = msg, %MessageContext{} = ctx) do
    if Map.get(ctx, :run_hooks, true) == false do
      {:ok, msg}
    else
      Pipeline.run_pre_send(msg, ctx)
    end
  end
end

defmodule IM.Hooks.PreSend.Noop do
  @moduledoc false
  @behaviour IM.Hooks.Behaviour

  @impl true
  def pre_send(msg, _ctx), do: {:ok, msg}

  # 兼容旧单 Hook 注入
  def run(msg, ctx), do: pre_send(msg, ctx)
end
