defmodule IMWeb.Api.V1.DeviceController do
  @moduledoc "设备相关：清本地数据 ACK、push_token 注册、管理封禁（MVP）。"

  use IMWeb, :controller

  action_fallback IMWeb.FallbackController

  alias IM.Application.Dispatch
  alias IM.Domain.Error
  alias IM.Services.DeviceBan
  alias IM.Stores.UserDeviceStore
  alias IMWeb.Api.V1.Json

  @doc """
  `POST /api/v1/devices/:device_id/local-data-cleared`
  """
  def local_data_cleared(conn, %{"device_id" => device_id}) do
    ctx = conn.assigns.message_context

    if ctx.device_id != device_id do
      {:error, Error.new(:unauthorized, "device_id mismatch")}
    else
      case Dispatch.execute(:ack_local_data_cleared, %{}, ctx) do
        {:ok, _} -> send_resp(conn, :no_content, "")
        {:error, %Error{} = err} -> {:error, err}
      end
    end
  end

  @doc """
  `PUT /api/v1/devices/:device_id/push-token` — 注册移动推送 token（不经 AuthReq）。
  """
  def update_push_token(conn, %{"device_id" => device_id} = params) do
    ctx = conn.assigns.message_context

    if ctx.device_id != device_id do
      {:error, Error.new(:unauthorized, "device_id mismatch")}
    else
      token = Json.str(params, "push_token")

      case UserDeviceStore.set_push_token(ctx.app_key, ctx.user_id, device_id, token) do
        {:ok, device} ->
          json(conn, %{
            device_id: device.device_id,
            push_token_registered: is_binary(device.push_token) and device.push_token != ""
          })

        {:error, %Error{} = err} ->
          {:error, err}
      end
    end
  end

  @doc """
  `POST /api/v1/devices/:device_id/ban`（管理端 MVP，同用户 token 可测）
  """
  def ban(conn, %{"device_id" => device_id} = params) do
    ctx = conn.assigns.message_context
    reason = Map.get(params, "reason", "admin")
    clear? = Map.get(params, "clear_local_data", false) in [true, "true"]

    case DeviceBan.ban(ctx.app_key, ctx.user_id, device_id, reason, clear_local_data: clear?) do
      :ok -> send_resp(conn, :no_content, "")
      {:error, %Error{} = err} -> {:error, err}
    end
  end
end

