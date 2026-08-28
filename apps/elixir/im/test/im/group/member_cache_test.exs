defmodule IM.Group.MemberCacheTest do
  use IM.DataCase, async: false

  alias IM.AuthFixtures
  alias IM.Cache.Memory
  alias IM.Domain.MessageContext
  alias IM.Group.MemberCache
  alias IM.Permission.L1
  alias IM.Services.Group

  setup do
    Memory.reset!()
    L1.reset!()
    owner = AuthFixtures.create_user!(user_id: "mc_o_#{System.unique_integer([:positive])}")

    peer =
      AuthFixtures.create_user!(
        app_key: owner.app_key,
        user_id: "mc_p_#{System.unique_integer([:positive])}"
      )

    ctx = %MessageContext{
      app_key: owner.app_key,
      user_id: owner.user_id,
      device_id: "d",
      session_id: "s",
      trace_id: "t",
      node: node()
    }

    {:ok, group} = Group.create(%{"name" => "c", "member_uids" => [peer.user_id]}, ctx)

    %{owner: owner, peer: peer, group: group, ctx: ctx}
  end

  test "member? 与 list_member_ids 写穿", %{peer: peer, group: group, ctx: ctx} do
    assert MemberCache.member?(ctx.app_key, group.group_id, peer.user_id)
    assert peer.user_id in MemberCache.list_member_ids(ctx.app_key, group.group_id)

    leave_ctx = %{ctx | user_id: peer.user_id}

    assert {:ok, _} =
             Group.leave(%Pb.Im.Protocol.GroupOperateReq{group_id: group.group_id}, leave_ctx)

    refute MemberCache.member?(ctx.app_key, group.group_id, peer.user_id)
    refute peer.user_id in MemberCache.list_member_ids(ctx.app_key, group.group_id)
  end
end
