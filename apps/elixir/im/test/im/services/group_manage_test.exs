defmodule IM.Services.GroupManageTest do
  use IM.DataCase, async: true

  alias IM.AuthFixtures
  alias IM.Domain.MessageContext
  alias IM.Services.Group
  alias IM.Stores.GroupStore
  alias Pb.Im.Protocol.{
    GroupAdminReq,
    GroupCreateReq,
    GroupInviteReq,
    GroupKickReq,
    GroupOperateReq,
    GroupTransferReq,
    GroupUpdateReq
  }

  setup do
    owner = AuthFixtures.create_user!(user_id: "go_#{System.unique_integer([:positive])}")
    m1 = AuthFixtures.create_user!(app_key: owner.app_key, user_id: "g1_#{System.unique_integer([:positive])}")
    m2 = AuthFixtures.create_user!(app_key: owner.app_key, user_id: "g2_#{System.unique_integer([:positive])}")
    outsider = AuthFixtures.create_user!(app_key: owner.app_key, user_id: "gx_#{System.unique_integer([:positive])}")

    ctx = ctx(owner, "d-owner")
    %{owner: owner, m1: m1, m2: m2, outsider: outsider, ctx: ctx}
  end

  test "WS 建群返回 GroupCreateResp 并写入成员", %{ctx: ctx, m1: m1} do
    assert {:ok, result} =
             Group.create(
               %GroupCreateReq{name: "team", member_uids: [m1.user_id]},
               ctx
             )

    assert result.resp.group_id != ""
    assert result.resp.conv_id == "g:#{result.resp.group_id}"
    assert m1.user_id in result.notify_user_ids
    assert GroupStore.member?(ctx.app_key, result.resp.group_id, ctx.user_id)
    assert GroupStore.member?(ctx.app_key, result.resp.group_id, m1.user_id)
  end

  test "邀请与踢人权限", %{ctx: ctx, m1: m1, m2: m2, outsider: outsider} do
    assert {:ok, created} =
             Group.create(%GroupCreateReq{name: "g", member_uids: [m1.user_id]}, ctx)

    gid = created.resp.group_id

    assert {:ok, inv} =
             Group.invite(%GroupInviteReq{group_id: gid, member_uids: [m2.user_id]}, ctx)

    assert m2.user_id in inv.push.member_uids
    assert GroupStore.member?(ctx.app_key, gid, m2.user_id)

    m1_ctx = ctx(m1, "d-m1")

    assert {:error, %{code: :group_no_permission}} =
             Group.kick(
               %GroupKickReq{group_id: gid, member_uids: [m2.user_id]},
               m1_ctx
             )

    assert {:ok, kicked} =
             Group.kick(%GroupKickReq{group_id: gid, member_uids: [m2.user_id]}, ctx)

    assert m2.user_id in kicked.push.member_uids
    refute GroupStore.member?(ctx.app_key, gid, m2.user_id)

    assert {:error, %{code: :group_not_member}} =
             Group.invite(
               %GroupInviteReq{group_id: gid, member_uids: [m1.user_id]},
               ctx(outsider, "d-x")
             )
  end

  test "设管、转让、更新、解散", %{ctx: ctx, m1: m1, m2: m2} do
    assert {:ok, created} =
             Group.create(
               %GroupCreateReq{name: "g", member_uids: [m1.user_id, m2.user_id]},
               ctx
             )

    gid = created.resp.group_id

    assert {:ok, _} =
             Group.set_admin(%GroupAdminReq{group_id: gid, member_uid: m1.user_id}, ctx)

    {:ok, admin} = GroupStore.get_member(ctx.app_key, gid, m1.user_id)
    assert admin.role == GroupStore.role_admin()

    assert {:ok, _} =
             Group.update(%GroupUpdateReq{group_id: gid, name: "renamed"}, ctx)

    {:ok, g} = GroupStore.get(ctx.app_key, gid)
    assert g.name == "renamed"

    assert {:ok, tr} =
             Group.transfer(%GroupTransferReq{group_id: gid, new_owner_uid: m1.user_id}, ctx)

    assert tr.push.new_owner_uid == m1.user_id
    {:ok, g2} = GroupStore.get(ctx.app_key, gid)
    assert g2.owner_uid == m1.user_id

    # 原群主已非 owner，解散应失败
    assert {:error, %{code: :group_no_permission}} =
             Group.dismiss(%GroupOperateReq{group_id: gid}, ctx)

    assert {:ok, _} =
             Group.dismiss(%GroupOperateReq{group_id: gid}, ctx(m1, "d-m1"))

    assert {:error, :not_found} = GroupStore.get(ctx.app_key, gid)
  end

  test "群主退群需先转让", %{ctx: ctx, m1: m1} do
    assert {:ok, created} =
             Group.create(%GroupCreateReq{name: "g", member_uids: [m1.user_id]}, ctx)

    assert {:error, %{code: :group_no_permission}} =
             Group.leave(%GroupOperateReq{group_id: created.resp.group_id}, ctx)
  end

  test "Router 注册群管理命令" do
    alias IM.Protocol.Router
    alias Pb.Im.Protocol.CmdType

    assert {:ok, IM.WebSocket.Commands.Group.Create} =
             Router.route(CmdType.value(:CMD_GROUP_CREATE_REQ))

    assert {:ok, IM.WebSocket.Commands.Group.Kick} =
             Router.route(CmdType.value(:CMD_GROUP_KICK_REQ))

    assert {:ok, IM.WebSocket.Commands.Group.Transfer} =
             Router.route(CmdType.value(:CMD_GROUP_TRANSFER_REQ))
  end

  defp ctx(user, device) do
    %MessageContext{
      app_key: user.app_key,
      user_id: user.user_id,
      device_id: device,
      session_id: "s-#{device}",
      trace_id: "t",
      node: node()
    }
  end
end
