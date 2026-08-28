defmodule IMWeb.Internal.V1.UserController do
  @moduledoc "内部：踢人 / 代发。"

  use IMWeb, :controller

  action_fallback IMWeb.FallbackController

  alias IM.Application.Dispatch
  alias IM.Domain.{Error, MessageContext}
  alias IM.Services.{Kick, User}
  alias IMWeb.Api.V1.Json
  alias Pb.Im.Protocol.{ChatMessage, CmdType, MsgSendReq}

  @doc "`POST /internal/v1/users/:user_id/kick`"
  def kick(conn, %{"user_id" => user_id} = params) do
    app_key = Json.str(params, "app_key")
    clear? = Map.get(params, "clear_local_data") in [true, "true", 1, "1"]

    :ok =
      Kick.kick_user(app_key, user_id,
        reason: Json.str(params, "reason", "admin_kick"),
        reason_code: :KICK_REASON_ADMIN_KICK,
        clear_local_data: clear?,
        trace_id: conn.assigns[:trace_id] || ""
      )

    json(conn, %{ok: true, user_id: user_id, caller_service: conn.assigns[:caller_service]})
  end

  @doc "`POST /internal/v1/users/:user_id/provision` 预置/更新用户（压测、冒烟）。"
  def provision(conn, %{"user_id" => user_id} = params) do
    case User.provision(Map.put(params, "user_id", user_id)) do
      {:ok, user} ->
        json(conn, %{
          user_id: user.user_id,
          app_key: user.app_key,
          provisioned: true,
          caller_service: conn.assigns[:caller_service]
        })

      {:error, %Error{} = err} ->
        {:error, err}
    end
  end

  @doc "`POST /internal/v1/users/:user_id/messages` 服务端代发"
  def create_message(conn, %{"user_id" => from_user_id} = params) do
    app_key = Json.str(params, "app_key")
    device_id = Json.str(params, "device_id", "internal")

    ctx =
      MessageContext.from_http_internal(%{
        app_key: app_key,
        user_id: from_user_id,
        device_id: device_id,
        session_id: "internal",
        trace_id: conn.assigns[:trace_id] || "internal",
        caller_service: conn.assigns[:caller_service],
        client_ip: conn.assigns[:client_ip],
        node: node(),
        run_hooks: Map.get(params, "run_hooks", true) not in [false, "false", 0, "0"]
      })

    msg = %ChatMessage{
      client_msg_id: Json.str(params, "client_msg_id"),
      chat_type: :CHAT_PRIVATE,
      from: from_user_id,
      to: Json.str(params, "to"),
      msg_type: :MSG_TEXT,
      content: Json.str(params, "content")
    }

    cmd = CmdType.value(:CMD_MSG_SEND)

    case Dispatch.execute(cmd, %MsgSendReq{message: msg}, ctx) do
      {:ok, %{message: message, ack: ack, duplicate?: dup?}} ->
        json(conn, %{
          msg_id: message.msg_id,
          client_msg_id: message.client_msg_id,
          conv_id: message.conv_id,
          status: to_string(ack.status),
          duplicate: dup?,
          caller_service: ctx.caller_service,
          source: to_string(ctx.source)
        })

      {:error, %Error{} = err} ->
        {:error, %{err | ref_cmd: cmd}}
    end
  end
end
