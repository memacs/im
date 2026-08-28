defmodule IM.Permission.ReconcilerTest do
  use IM.DataCase, async: false

  alias IM.AuthFixtures
  alias IM.Cache.Memory
  alias IM.Domain.MessageContext
  alias IM.Jobs.PermissionReconcile
  alias IM.Permission.{BlockCache, L1, Reconciler}
  alias IM.Services.{DeviceBan, Friend, Group}
  alias IM.Stores.GroupStore
  alias Pb.Im.Protocol.{FriendAcceptReq, FriendBlockReq, GroupCreateReq}

  setup do
    Memory.reset!()
    L1.reset!()
    a = AuthFixtures.create_user!(user_id: "rc_a_#{System.unique_integer([:positive])}")

    b =
      AuthFixtures.create_user!(
        app_key: a.app_key,
        user_id: "rc_b_#{System.unique_integer([:positive])}"
      )

    %{a: a, b: b}
  end

  defp ctx(user) do
    %MessageContext{
      app_key: user.app_key,
      user_id: user.user_id,
      device_id: "d-#{user.user_id}",
      session_id: "s",
      trace_id: "t",
      node: node()
    }
  end

  test "修复 L2 缺失的拉黑成员", %{a: a, b: b} do
    assert {:ok, _} = Friend.block(%FriendBlockReq{user_id: b.user_id}, ctx(a))

    Memory.reset!()
    L1.reset!()

    result = PermissionReconcile.run_once(a.app_key, sample: 50)
    assert result.block >= 1
    assert BlockCache.blocked?(a.app_key, a.user_id, b.user_id)
  end

  test "run/2 对账 mute / device / group / friendship", %{a: a, b: b} do
    c = ctx(a)

    assert {:ok, %{resp: %{request_id: rid}}} =
             Friend.add(%Pb.Im.Protocol.FriendAddReq{to_user_id: b.user_id}, c)

    assert {:ok, _} = Friend.accept(%FriendAcceptReq{request_id: rid}, ctx(b))

    assert {:ok, %{group_id: gid}} =
             Group.create(%GroupCreateReq{name: "rc-g", member_uids: [b.user_id]}, c)

    until = System.system_time(:millisecond) + 120_000

    assert {:ok, _} =
             Group.mute_member(gid, b.user_id, until, c)

    assert :ok = DeviceBan.ban(a.app_key, a.user_id, "dev-ban", "test")

    Memory.reset!()
    L1.reset!()

    stats = Reconciler.run(a.app_key, sample: 50)
    assert is_integer(stats.block)
    assert stats.mute >= 0
    assert stats.device_ban >= 0
    assert stats.group_member >= 0
    assert stats.friendship >= 0

    assert MapSet.member?(GroupStore.list_member_ids(a.app_key, gid) |> MapSet.new(), b.user_id)
  end
end
