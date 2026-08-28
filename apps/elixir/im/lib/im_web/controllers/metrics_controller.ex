defmodule IMWeb.MetricsController do
  @moduledoc """
  Prometheus 抓取端点（P9-05）。

  仅供内网 / ServiceMonitor 使用；不鉴权（由网络策略保护）。
  """

  use IMWeb, :controller

  @doc """
  返回 Prometheus exposition format。

  ## 示例

      get(conn, "/metrics")
      #=> 200 text/plain; version=0.0.4
  """
  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def index(conn, _params) do
    body = IM.Telemetry.Supervisor.scrape()

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, body)
  end
end
