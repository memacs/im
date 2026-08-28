defmodule IM.Application.Dispatch do
  @moduledoc """
  cmd → Service 的**唯一**映射。WebSocket、REST、Kafka 三条入站路径都必须经此模块，
  任何一条绕过去自己实现业务，双通道语义就会漂移。

  设计见仓库根 `docs/implementation/elixir/dual-channel-api.md` §2。

  P0-05 骨架：注册表与鉴权门禁在 P2-10 落地，当前所有 cmd 返回 `:not_implemented`。
  """

  alias IM.Domain.{Error, MessageContext}

  @doc """
  执行一条命令。

  `cmd` 为 `CmdType` 枚举数值（见 `proto/common.proto`），`payload` 为已解码的请求体。
  失败一律返回 `IM.Domain.Error`，由调用方按出口翻译成 `CMD_ERROR` 或 HTTP 响应。
  """
  @spec execute(non_neg_integer(), map() | struct(), MessageContext.t()) ::
          {:ok, term()} | {:error, Error.t()}
  def execute(cmd, _payload, %MessageContext{}) when is_integer(cmd) do
    {:error, Error.not_implemented(cmd)}
  end
end
