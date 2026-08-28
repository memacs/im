defmodule IM.Protocol.Router do
  @moduledoc """
  WS 侧按 `cmd` 选择 `IM.WebSocket.Commands.*` 处理模块，并施加鉴权态门禁
  （未鉴权连接只放行 `CMD_AUTH_REQ`）与 `:telemetry.span`。

  **本模块不含业务**：业务在 `IM.Services.*`，经 `IM.Application.Dispatch` 进入。
  设计见仓库根 `docs/implementation/elixir/dual-channel-api.md` §1。

  P0-05 骨架：命令注册表随各 Command 模块在 Phase 1+ 逐条补齐。
  """

  alias IM.Domain.Error

  @doc """
  返回处理该 `cmd` 的 Command 模块。
  """
  @spec route(non_neg_integer()) :: {:ok, module()} | {:error, Error.t()}
  def route(cmd) when is_integer(cmd) do
    {:error, Error.not_implemented(cmd)}
  end
end
