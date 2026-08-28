defmodule IMWeb.HealthController do
  @moduledoc """
  健康检查端点，供 Kubernetes 探针与冒烟脚本调用。

  探针配置见 `deploy/elixir/im/k8s/im/deployment.yaml`；
  检查语义见 `IM.Health`。
  """

  use IMWeb, :controller

  @doc """
  存活探针：只要 BEAM 与 HTTP 监听正常就返回 200。

  失败会触发容器重启，因此**不做**任何依赖检查。

  ## 示例

      get(conn, ~p"/health/live")
      #=> 200 %{"status" => "ok"}

  """
  @spec live(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def live(conn, _params) do
    :ok = IM.Health.live?()
    json(conn, %{status: "ok"})
  end

  @doc """
  就绪探针：依赖（主库）可用时返回 200，否则 503。

  失败只会把本实例摘出负载均衡，不重启容器。

  ## 示例

      get(conn, ~p"/health/ready")
      #=> 200 %{"status" => "ok", "database" => "connected"}

  ## 返回值

  - 200 `%{"status" => "ok", "database" => "connected"}`
  - 503 `%{"status" => "error", "database" => "<原因>"}`
  """
  @spec ready(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def ready(conn, _params) do
    case IM.Health.ready?() do
      :ok ->
        json(conn, %{status: "ok", database: "connected"})

      {:error, reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{status: "error", database: inspect(reason)})
    end
  end
end
