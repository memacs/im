defmodule IM.Ingress.Http do
  @moduledoc """
  REST 侧薄适配：解析 → `Dispatch` → 由 Controller 渲染。

  登录等无 Bearer 的入口可直接调 `IM.Services.*`；已鉴权业务经本模块。
  """

  alias IM.Application.Dispatch
  alias IM.Domain.{Error, MessageContext}

  @doc """
  在已具备 `MessageContext` 时执行 Dispatch。

  ## 示例

      IM.Ingress.Http.dispatch(ctx, :ack_local_data_cleared, %{})
  """
  @spec dispatch(MessageContext.t(), atom() | non_neg_integer(), map() | struct()) ::
          {:ok, term()} | {:error, Error.t()}
  def dispatch(%MessageContext{} = ctx, cmd, payload) do
    Dispatch.execute(cmd, payload, ctx)
  end

  def dispatch(_conn_or_other, _cmd, _payload) do
    {:error, Error.new(:msg_invalid, "invalid ingress dispatch")}
  end
end
