defmodule IM.Permission.ReconcilerTest do
  use IM.DataCase, async: false

  alias IM.AuthFixtures
  alias IM.Cache.Memory
  alias IM.Domain.MessageContext
  alias IM.Jobs.PermissionReconcile
  alias IM.Permission.{BlockCache, L1}
  alias IM.Services.Friend
  alias Pb.Im.Protocol.FriendBlockReq

  setup do
    Memory.reset!()
    L1.reset!()
    a = AuthFixtures.create_user!(user_id: "rc_a_#{System.unique_integer([:positive])}")
    b = AuthFixtures.create_user!(app_key: a.app_key, user_id: "rc_b_#{System.unique_integer([:positive])}")
    %{a: a, b: b}
  end

  test "修复 L2 缺失的拉黑成员", %{a: a, b: b} do
    ctx = %MessageContext{
      app_key: a.app_key,
      user_id: a.user_id,
      device_id: "d",
      session_id: "s",
      trace_id: "t",
      node: node()
    }

    assert {:ok, _} = Friend.block(%FriendBlockReq{user_id: b.user_id}, ctx)

    # 模拟 L2 漂移：清空内存缓存但 PG 仍为 blocked
    Memory.reset!()
    L1.reset!()

    result = PermissionReconcile.run_once(a.app_key, sample: 50)
    assert result.block >= 1
    assert BlockCache.blocked?(a.app_key, a.user_id, b.user_id)
  end
end
