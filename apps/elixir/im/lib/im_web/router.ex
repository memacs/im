defmodule IMWeb.Router do
  @moduledoc """
  HTTP 路由。

  业务 REST 接口挂在 `/api/v1`（P2-11 起），与 WebSocket 命令共用
  `IM.Application.Dispatch`，见仓库根 `docs/design/dual-channel-api.md`。
  """

  use Phoenix.Router

  import Plug.Conn
  import Phoenix.Controller

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", IMWeb do
    pipe_through(:api)

    # 存活与就绪分离：liveness 不查库，readiness 查库
    get("/health/live", HealthController, :live)
    get("/health/ready", HealthController, :ready)
    # 兼容入口，语义等同 liveness（mise run release-smoke 使用）
    get("/health", HealthController, :live)
  end
end
