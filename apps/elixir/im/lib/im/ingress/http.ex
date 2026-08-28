defmodule IM.Ingress.Http do
  @moduledoc """
  REST 侧适配层（薄）：鉴权取上下文 → 解 body → `IM.Application.Dispatch.execute/3` → JSON。

  Controller 只做路由与参数绑定，业务一律经 Dispatch，禁止在 Controller 里复制
  Service 逻辑（见仓库根 `docs/implementation/elixir/dual-channel-api.md` §3）。

  P0-05 骨架：随 P2-11 的 `:api` pipeline 与 FallbackController 一起落地。
  """

  alias IM.Domain.Error

  @doc """
  把一次 HTTP 请求适配为一次 Dispatch 调用。`parse_fun` 负责把 conn body 解成 payload。
  """
  @spec dispatch(term(), non_neg_integer(), (term() -> {:ok, term()} | {:error, Error.t()})) ::
          {:ok, term()} | {:error, Error.t()}
  def dispatch(_conn, cmd, parse_fun) when is_integer(cmd) and is_function(parse_fun, 1) do
    {:error, Error.not_implemented(cmd)}
  end
end
