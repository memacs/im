defmodule IM.Permission.BlockCacheTest do
  use IM.DataCase, async: false

  alias IM.AuthFixtures
  alias IM.Cache.Memory
  alias IM.Domain.MessageContext
  alias IM.Permission.{BlockCache, L1}
  alias IM.Services.Friend
  alias Pb.Im.Protocol.FriendBlockReq

  setup do
    Memory.reset!()
    L1.reset!()
    a = AuthFixtures.create_user!(user_id: "bc_a_#{System.unique_integer([:positive])}")
    b = AuthFixtures.create_user!(app_key: a.app_key, user_id: "bc_b_#{System.unique_integer([:positive])}")
    %{a: a, b: b}
  end

  test "写穿 put/delete", %{a: a, b: b} do
    refute BlockCache.blocked?(a.app_key, a.user_id, b.user_id)
    :ok = BlockCache.put(a.app_key, a.user_id, b.user_id)
    assert BlockCache.blocked?(a.app_key, a.user_id, b.user_id)
    :ok = BlockCache.delete(a.app_key, a.user_id, b.user_id)
    refute BlockCache.blocked?(a.app_key, a.user_id, b.user_id)
  end

  test "Friend.block 后 messaging_blocked?", %{a: a, b: b} do
    ctx = %MessageContext{
      app_key: a.app_key,
      user_id: a.user_id,
      device_id: "d",
      session_id: "s",
      trace_id: "t",
      node: node()
    }

    assert {:ok, _} = Friend.block(%FriendBlockReq{user_id: b.user_id}, ctx)
    assert BlockCache.messaging_blocked?(a.app_key, a.user_id, b.user_id)
  end
end
