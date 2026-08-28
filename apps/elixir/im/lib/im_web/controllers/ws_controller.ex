defmodule IMWeb.WsController do
  @moduledoc "升级 HTTP 连接为二进制 Packet WebSocket（`/ws`）。"

  use IMWeb, :controller

  @doc false
  def upgrade(conn, _params) do
    conn
    |> WebSockAdapter.upgrade(IMWeb.PacketTransport, %{}, timeout: 90_000)
    |> halt()
  end
end
