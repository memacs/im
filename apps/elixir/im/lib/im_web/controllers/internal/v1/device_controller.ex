defmodule IMWeb.Internal.V1.DeviceController do
  @moduledoc "内部：踢设备 / 封禁设备。"

  use IMWeb, :controller

  action_fallback IMWeb.FallbackController

  alias IM.Domain.Error
  alias IM.Services.{DeviceBan, Kick}
  alias IMWeb.Api.V1.Json

  @doc "`POST /internal/v1/devices/:device_id/kick`"
  def kick(conn, %{"device_id" => device_id} = params) do
    app_key = Json.str(params, "app_key")
    user_id = Json.str(params, "user_id")
    clear? = Map.get(params, "clear_local_data") in [true, "true", 1, "1"]

    case Kick.kick_device(app_key, user_id, device_id,
           reason: Json.str(params, "reason", "admin_kick"),
           reason_code: :KICK_REASON_ADMIN_KICK,
           clear_local_data: clear?,
           trace_id: conn.assigns[:trace_id] || ""
         ) do
      :ok -> json(conn, %{ok: true, device_id: device_id})
      {:error, %Error{} = err} -> {:error, err}
    end
  end

  @doc "`POST /internal/v1/devices/:device_id/ban`"
  def ban(conn, %{"device_id" => device_id} = params) do
    app_key = Json.str(params, "app_key")
    user_id = Json.str(params, "user_id")
    reason = Json.str(params, "reason", "banned")
    clear? = Map.get(params, "clear_local_data") in [true, "true", 1, "1"]

    case DeviceBan.ban(app_key, user_id, device_id, reason, clear_local_data: clear?) do
      :ok -> json(conn, %{ok: true, device_id: device_id, banned: true})
      {:error, %Error{} = err} -> {:error, err}
    end
  end
end
