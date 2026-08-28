defmodule IMWeb do
  @moduledoc """
  Web 层（REST + WebSocket 接入）的公共入口定义。

  在模块中 `use IMWeb, :controller` 引入控制器所需的导入与别名。
  接入层保持「薄」：解析请求 → `IM.Application.Dispatch` → 渲染响应，
  业务规则一律写在 `IM.Services.*`（见仓库根 `docs/design/dual-channel-api.md`）。
  """

  @doc """
  控制器模板。

  ## 示例

      defmodule IMWeb.HealthController do
        use IMWeb, :controller
      end

  """
  def controller do
    quote do
      use Phoenix.Controller, formats: [:json]

      import Plug.Conn

      unquote(verified_routes())
    end
  end

  @doc """
  路由校验模板，提供 `~p` sigil。

  ## 示例

      use IMWeb, :verified_routes

  """
  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: IMWeb.Endpoint,
        router: IMWeb.Router
    end
  end

  @doc """
  按名称展开对应模板。

  ## 示例

      use IMWeb, :controller

  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
