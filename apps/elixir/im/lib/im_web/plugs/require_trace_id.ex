defmodule IMWeb.Plugs.RequireTraceId do
  @moduledoc "要求请求头 `X-Trace-Id`（dual-channel-api §4.2）。"

  import Plug.Conn

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case get_req_header(conn, "x-trace-id") do
      [trace_id | _] when trace_id != "" ->
        assign(conn, :trace_id, trace_id)

      _ ->
        conn
        |> put_status(:bad_request)
        |> Phoenix.Controller.json(%{code: 2001, msg: "missing X-Trace-Id"})
        |> halt()
    end
  end
end
