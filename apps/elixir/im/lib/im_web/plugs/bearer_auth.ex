defmodule IMWeb.Plugs.BearerAuth do
  @moduledoc "校验 `Authorization: Bearer <access_token>`，与 WS AUTH 同源。"

  import Plug.Conn

  @behaviour Plug

  alias IM.Domain.MessageContext

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, claims} <- IM.Auth.verify_token(token) do
      ctx =
        MessageContext.from_http_client(%{
          app_key: claims.app_key,
          user_id: claims.user_id,
          device_id: claims.device_id,
          trace_id: conn.assigns[:trace_id] || Ecto.UUID.generate(),
          client_ip: client_ip(conn),
          node: node()
        })

      conn
      |> assign(:current_claims, claims)
      |> assign(:message_context, ctx)
      |> assign(:access_token, token)
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(%{code: 1001, msg: "unauthorized"})
        |> halt()
    end
  end

  defp client_ip(conn) do
    case conn.remote_ip do
      ip when is_tuple(ip) -> ip |> :inet.ntoa() |> to_string()
      _ -> nil
    end
  end
end
