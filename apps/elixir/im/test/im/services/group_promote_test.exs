defmodule IM.Services.GroupPromoteTest do
  use IM.DataCase, async: false

  alias IM.AuthFixtures
  alias IM.Domain.MessageContext
  alias IM.Group.MetaCache
  alias IM.Services.Group
  alias IM.Stores.GroupStore
  alias Pb.Im.Protocol.GroupOperateReq

  @tag :group_promote
  test "扩员超过 read_fanout_threshold 时自动晋升并写穿 MetaCache" do
    prev = Application.get_env(:im, :group_fanout, [])
    Application.put_env(:im, :group_fanout, Keyword.put(prev, :read_fanout_threshold, 2))

    on_exit(fn -> Application.put_env(:im, :group_fanout, prev) end)

    owner = AuthFixtures.create_user!(user_id: "gp_o_#{System.unique_integer([:positive])}")
    m1 = AuthFixtures.create_user!(app_key: owner.app_key, user_id: "gp_m1_#{System.unique_integer([:positive])}")
    m2 = AuthFixtures.create_user!(app_key: owner.app_key, user_id: "gp_m2_#{System.unique_integer([:positive])}")

    ctx = %MessageContext{
      app_key: owner.app_key,
      user_id: owner.user_id,
      device_id: "d",
      session_id: "s",
      trace_id: "t",
      node: node()
    }

    {:ok, %{group_id: group_id}} =
      Group.create(%{"name" => "promo", "member_uids" => [m1.user_id]}, ctx)

    {:ok, g0} = GroupStore.get(owner.app_key, group_id)
    assert g0.storage_mode == "write_fanout"

    join_ctx = %{ctx | user_id: m2.user_id}
    assert {:ok, _} = Group.join(%GroupOperateReq{group_id: group_id}, join_ctx)

    {:ok, g1} = GroupStore.get(owner.app_key, group_id)
    assert g1.storage_mode == "read_fanout"

    {:ok, cached} = MetaCache.get(owner.app_key, group_id)
    assert cached.storage_mode == "read_fanout"
  end
end
