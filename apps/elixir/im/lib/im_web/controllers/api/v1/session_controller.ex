defmodule IMWeb.Api.V1.SessionController do
  @moduledoc "HTTP 登录 / 登出。"

  use IMWeb, :controller

  action_fallback(IMWeb.FallbackController)

  alias IM.Domain.Error
  alias IM.Services.Session

  @doc """
  `POST /api/v1/sessions`
  """
  def create(conn, params) do
    case Session.create(params) do
      {:ok, body} ->
        json(conn, body)

      {:error, %Error{msg: "device_banned"} = err} ->
        conn
        |> put_status(:forbidden)
        |> json(%{code: 1001, msg: err.msg})

      {:error, %Error{} = err} ->
        {:error, err}
    end
  end

  @doc """
  `DELETE /api/v1/sessions/current`
  """
  def delete_current(conn, _params) do
    token = conn.assigns[:access_token]
    ctx = conn.assigns[:message_context]

    case Session.revoke(token) do
      :ok ->
        if match?(%IM.Domain.MessageContext{}, ctx) do
          _ = IM.EventBus.Session.logout(ctx, "http_logout")

          IM.Audit.record(:auth_logout,
            app_key: ctx.app_key,
            user_id: ctx.user_id,
            device_id: ctx.device_id,
            strategy: "token",
            result: :success,
            reason: "http_logout",
            client_ip: ctx.client_ip
          )
        end

        send_resp(conn, :no_content, "")

      {:error, %Error{} = err} ->
        {:error, err}
    end
  end
end
