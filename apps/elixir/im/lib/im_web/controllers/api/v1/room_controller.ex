defmodule IMWeb.Api.V1.RoomController do
  @moduledoc "聊天室 REST（与 WS `CMD_ROOM_*` 同 Dispatch；无 PubSub 副作用）。"

  use IMWeb, :controller

  action_fallback(IMWeb.FallbackController)

  alias IM.Application.Dispatch
  alias IM.Domain.Error
  alias IMWeb.Api.V1.Json

  alias Pb.Im.Protocol.{
    ChatMessage,
    CmdType,
    MsgSendReq,
    RoomCreateReq,
    RoomKickReq,
    RoomOperateReq,
    RoomUpdateReq
  }

  def create(conn, params) do
    max = Json.int(params, "max_members", 0)

    req = %RoomCreateReq{
      room_id: Json.str(params, "room_id"),
      name: Json.str(params, "name"),
      max_members: max,
      persist_msg: truthy?(params, "persist_msg"),
      msg_ttl_sec: Json.int(params, "msg_ttl_sec", 0)
    }

    dispatch(conn, :CMD_ROOM_CREATE_REQ, req, :created)
  end

  def dismiss(conn, %{"room_id" => room_id} = params) do
    dispatch(conn, :CMD_ROOM_DISMISS_REQ, %RoomOperateReq{
      room_id: room_id,
      reason: Json.str(params, "reason")
    })
  end

  def join(conn, %{"room_id" => room_id}) do
    dispatch(conn, :CMD_ROOM_JOIN_REQ, %RoomOperateReq{room_id: room_id})
  end

  def leave(conn, %{"room_id" => room_id}) do
    dispatch(conn, :CMD_ROOM_LEAVE_REQ, %RoomOperateReq{room_id: room_id})
  end

  def kick(conn, %{"room_id" => room_id} = params) do
    uids = list_uids(params, "member_uids")

    dispatch(conn, :CMD_ROOM_KICK_REQ, %RoomKickReq{
      room_id: room_id,
      member_uids: uids,
      reason: Json.str(params, "reason")
    })
  end

  def update(conn, %{"room_id" => room_id} = params) do
    dispatch(conn, :CMD_ROOM_UPDATE_REQ, %RoomUpdateReq{
      room_id: room_id,
      name: Json.str(params, "name"),
      max_members: Json.int(params, "max_members", 0),
      persist_msg: truthy?(params, "persist_msg"),
      msg_ttl_sec: Json.int(params, "msg_ttl_sec", 0)
    })
  end

  def create_message(conn, %{"room_id" => room_id} = params) do
    ctx = conn.assigns.message_context
    cmd = CmdType.value(:CMD_MSG_SEND)

    msg = %ChatMessage{
      client_msg_id: Json.str(params, "client_msg_id"),
      chat_type: :CHAT_ROOM,
      from: ctx.user_id,
      to: room_id,
      conv_id: Json.str(params, "conv_id", "r:#{room_id}"),
      msg_type: :MSG_TEXT,
      content: content_bin(params),
      target_users: list_uids(params, "target_users")
    }

    case Dispatch.execute(cmd, %MsgSendReq{message: msg}, ctx) do
      {:ok, %{message: message, ack: ack, duplicate?: dup?}} ->
        json(conn, %{
          msg_id: message.msg_id,
          client_msg_id: message.client_msg_id,
          conv_id: message.conv_id,
          conv_seq: message.conv_seq,
          server_time: message.server_time,
          status: to_string(ack.status),
          duplicate: dup?
        })

      {:error, %Error{} = err} ->
        {:error, %{err | ref_cmd: cmd}}
    end
  end

  defp dispatch(conn, cmd_atom, payload, status \\ :ok) do
    ctx = conn.assigns.message_context
    cmd = CmdType.value(cmd_atom)

    case Dispatch.execute(cmd, payload, ctx) do
      {:ok, %{resp: resp}} ->
        conn |> put_status(status) |> json(Json.encode(resp))

      {:ok, %{push: push}} ->
        json(conn, Json.encode(push))

      {:ok, other} ->
        conn |> put_status(status) |> json(Json.encode(other))

      {:error, %Error{} = err} ->
        {:error, %{err | ref_cmd: cmd}}
    end
  end

  defp list_uids(params, key) do
    raw = Map.get(params, key) || Map.get(params, String.to_atom(key)) || []
    raw |> List.wrap() |> Enum.map(&to_string/1) |> Enum.reject(&(&1 == ""))
  end

  defp content_bin(params) do
    case Map.get(params, "content") || Map.get(params, :content) || "" do
      bin when is_binary(bin) -> bin
      other -> to_string(other)
    end
  end

  defp truthy?(params, key) do
    case Map.get(params, key) || Map.get(params, String.to_atom(key)) do
      true -> true
      "true" -> true
      1 -> true
      "1" -> true
      _ -> false
    end
  end
end
