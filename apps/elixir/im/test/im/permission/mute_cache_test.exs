defmodule IM.Permission.MuteCacheTest do
  use IM.DataCase, async: false

  alias IM.AuthFixtures
  alias IM.Cache.Memory
  alias IM.Domain.MessageContext
  alias IM.Permission.{L1, MuteCache}
  alias IM.Services.Group
  alias Pb.Im.Protocol.GroupCreateReq

  setup do
    Memory.reset!()
    L1.reset!()
    owner = AuthFixtures.create_user!(user_id: "mute_o_#{System.unique_integer([:positive])}")
    member = AuthFixtures.create_user!(app_key: owner.app_key, user_id: "mute_m_#{System.unique_integer([:positive])}")

    ctx = %MessageContext{
      app_key: owner.app_key,
      user_id: owner.user_id,
      device_id: "d",
      session_id: "s",
      trace_id: "t",
      node: node()
    }

    assert {:ok, group} =
             Group.create(
               %GroupCreateReq{
                 name: "g",
                 member_uids: [member.user_id]
               },
               ctx
             )

    %{owner: owner, member: member, group: group, ctx: ctx}
  end

  test "mute_member 写穿后 muted?", %{member: member, group: group, ctx: ctx} do
    until = System.system_time(:millisecond) + 60_000
    refute MuteCache.muted?(ctx.app_key, group.group_id, member.user_id)

    assert {:ok, _} = Group.mute_member(group.group_id, member.user_id, until, ctx)
    assert MuteCache.muted?(ctx.app_key, group.group_id, member.user_id)

    assert {:ok, _} = Group.mute_member(group.group_id, member.user_id, 0, ctx)
    refute MuteCache.muted?(ctx.app_key, group.group_id, member.user_id)
  end
end
