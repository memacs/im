defmodule IMWeb.Api.V1.GroupController do
  @moduledoc "群组 REST（与 WS `CMD_GROUP_*` 同 Dispatch）。"

  use IMWeb, :controller

  action_fallback(IMWeb.FallbackController)

  alias IM.Application.Dispatch
  alias IM.Domain.Error
  alias IMWeb.Api.V1.Json

  alias Pb.Im.Protocol.{
    CmdType,
    GroupAdminReq,
    GroupCreateReq,
    GroupInviteReq,
    GroupKickReq,
    GroupOperateReq,
    GroupTransferReq,
    GroupUpdateReq
  }

  def create(conn, params) do
    req = %GroupCreateReq{
      name: Json.str(params, "name"),
      group_id: Json.str(params, "group_id"),
      member_uids: list_uids(params, "member_uids"),
      announcement: Json.str(params, "announcement"),
      max_members: Json.int(params, "max_members", 0)
    }

    ctx = conn.assigns.message_context
    cmd = CmdType.value(:CMD_GROUP_CREATE_REQ)

    case Dispatch.execute(cmd, req, ctx) do
      {:ok, body} ->
        conn
        |> put_status(:created)
        |> json(%{
          group_id: body.group_id,
          name: body.name,
          conv_id: body.conv_id,
          owner_uid: body.owner_uid,
          member_count: body.member_count,
          storage_mode: body.storage_mode
        })

      {:error, %Error{} = err} ->
        {:error, %{err | ref_cmd: cmd}}
    end
  end

  def dismiss(conn, %{"group_id" => group_id} = params) do
    dispatch_op(conn, :CMD_GROUP_DISMISS_REQ, %GroupOperateReq{
      group_id: group_id,
      reason: Json.str(params, "reason")
    })
  end

  def join(conn, %{"group_id" => group_id}) do
    dispatch_op(conn, :CMD_GROUP_JOIN_REQ, %GroupOperateReq{group_id: group_id})
  end

  def leave(conn, %{"group_id" => group_id}) do
    dispatch_op(conn, :CMD_GROUP_LEAVE_REQ, %GroupOperateReq{group_id: group_id})
  end

  def kick(conn, %{"group_id" => group_id} = params) do
    dispatch_op(conn, :CMD_GROUP_KICK_REQ, %GroupKickReq{
      group_id: group_id,
      member_uids: list_uids(params, "member_uids"),
      reason: Json.str(params, "reason")
    })
  end

  def invite(conn, %{"group_id" => group_id} = params) do
    dispatch_op(conn, :CMD_GROUP_INVITE_REQ, %GroupInviteReq{
      group_id: group_id,
      member_uids: list_uids(params, "member_uids")
    })
  end

  def set_admin(conn, %{"group_id" => group_id} = params) do
    dispatch_op(conn, :CMD_GROUP_SET_ADMIN_REQ, %GroupAdminReq{
      group_id: group_id,
      member_uid: Json.str(params, "member_uid")
    })
  end

  def remove_admin(conn, %{"group_id" => group_id} = params) do
    dispatch_op(conn, :CMD_GROUP_REMOVE_ADMIN_REQ, %GroupAdminReq{
      group_id: group_id,
      member_uid: Json.str(params, "member_uid")
    })
  end

  def transfer(conn, %{"group_id" => group_id} = params) do
    dispatch_op(conn, :CMD_GROUP_TRANSFER_REQ, %GroupTransferReq{
      group_id: group_id,
      new_owner_uid: Json.str(params, "new_owner_uid")
    })
  end

  def update(conn, %{"group_id" => group_id} = params) do
    dispatch_op(conn, :CMD_GROUP_UPDATE_REQ, %GroupUpdateReq{
      group_id: group_id,
      name: Json.str(params, "name"),
      announcement: Json.str(params, "announcement"),
      max_members: Json.int(params, "max_members", 0)
    })
  end

  @doc "`POST /api/v1/groups/:group_id/mute` body: member_uid, muted_until (ms)"
  def mute(conn, %{"group_id" => group_id} = params) do
    ctx = conn.assigns.message_context

    case Dispatch.execute(
           :group_mute,
           %{
             group_id: group_id,
             member_uid: Json.str(params, "member_uid"),
             muted_until: Json.int(params, "muted_until", 0)
           },
           ctx
         ) do
      {:ok, body} -> json(conn, body)
      {:error, %Error{} = err} -> {:error, err}
    end
  end

  defp dispatch_op(conn, cmd_atom, payload) do
    ctx = conn.assigns.message_context
    cmd = CmdType.value(cmd_atom)

    case Dispatch.execute(cmd, payload, ctx) do
      {:ok, %{push: push}} ->
        json(conn, Json.encode(push))

      {:ok, %{resp: resp}} ->
        json(conn, Json.encode(resp))

      {:ok, other} ->
        json(conn, Json.encode(other))

      {:error, %Error{} = err} ->
        {:error, %{err | ref_cmd: cmd}}
    end
  end

  defp list_uids(params, key) do
    raw = Map.get(params, key) || Map.get(params, String.to_atom(key)) || []
    raw |> List.wrap() |> Enum.map(&to_string/1) |> Enum.reject(&(&1 == ""))
  end
end
