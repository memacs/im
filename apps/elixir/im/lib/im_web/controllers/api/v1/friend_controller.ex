defmodule IMWeb.Api.V1.FriendController do
  @moduledoc "好友 REST（与 WS `CMD_FRIEND_*` 同 Dispatch）。"

  use IMWeb, :controller

  action_fallback(IMWeb.FallbackController)

  alias IM.Application.Dispatch
  alias IM.Domain.Error
  alias IMWeb.Api.V1.Json

  alias Pb.Im.Protocol.{
    CmdType,
    FriendAcceptReq,
    FriendAddReq,
    FriendBlockReq,
    FriendDeleteReq,
    FriendListReq,
    FriendRejectReq,
    FriendRequestListReq,
    FriendSetRemarkReq,
    FriendUnblockReq
  }

  def add(conn, params) do
    dispatch(conn, :CMD_FRIEND_ADD_REQ, %FriendAddReq{
      to_user_id: Json.str(params, "to_user_id"),
      message: Json.str(params, "message"),
      remark: Json.str(params, "remark")
    })
  end

  def accept(conn, params) do
    dispatch(conn, :CMD_FRIEND_ACCEPT_REQ, %FriendAcceptReq{
      request_id: Json.str(params, "request_id"),
      from_user_id: Json.str(params, "from_user_id"),
      remark: Json.str(params, "remark")
    })
  end

  def reject(conn, params) do
    dispatch(conn, :CMD_FRIEND_REJECT_REQ, %FriendRejectReq{
      request_id: Json.str(params, "request_id")
    })
  end

  def delete(conn, params) do
    dispatch(conn, :CMD_FRIEND_DELETE_REQ, %FriendDeleteReq{
      friend_user_id: Json.str(params, "friend_user_id") || Json.str(params, "user_id")
    })
  end

  def block(conn, params) do
    dispatch(conn, :CMD_FRIEND_BLOCK_REQ, %FriendBlockReq{
      user_id: Json.str(params, "user_id")
    })
  end

  def unblock(conn, params) do
    dispatch(conn, :CMD_FRIEND_UNBLOCK_REQ, %FriendUnblockReq{
      user_id: Json.str(params, "user_id")
    })
  end

  def set_remark(conn, params) do
    dispatch(conn, :CMD_FRIEND_SET_REMARK_REQ, %FriendSetRemarkReq{
      friend_user_id: Json.str(params, "friend_user_id"),
      remark: Json.str(params, "remark")
    })
  end

  def index(conn, _params) do
    dispatch(conn, :CMD_FRIEND_LIST_REQ, %FriendListReq{})
  end

  def requests(conn, _params) do
    dispatch(conn, :CMD_FRIEND_REQUEST_LIST_REQ, %FriendRequestListReq{})
  end

  defp dispatch(conn, cmd_atom, payload) do
    ctx = conn.assigns.message_context
    cmd = CmdType.value(cmd_atom)

    case Dispatch.execute(cmd, payload, ctx) do
      {:ok, %{resp: resp}} ->
        json(conn, Json.encode(resp))

      {:ok, other} ->
        json(conn, Json.encode(other))

      {:error, %Error{} = err} ->
        {:error, %{err | ref_cmd: cmd}}
    end
  end
end
