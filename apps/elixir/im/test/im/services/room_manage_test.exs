defmodule IM.Services.RoomManageTest do
  use IM.DataCase, async: true

  alias IM.AuthFixtures
  alias IM.Domain.MessageContext
  alias IM.Services.Room
  alias IM.Stores.RoomStore
  alias Pb.Im.Protocol.{RoomCreateReq, RoomKickReq, RoomOperateReq, RoomUpdateReq}

  setup do
    owner = AuthFixtures.create_user!(user_id: "ro_#{System.unique_integer([:positive])}")
    peer = AuthFixtures.create_user!(app_key: owner.app_key, user_id: "rp_#{System.unique_integer([:positive])}")
    %{owner: owner, peer: peer, ctx: ctx(owner, "d"), peer_ctx: ctx(peer, "dp")}
  end

  test "更新与踢人与解散", %{ctx: ctx, peer: peer, peer_ctx: peer_ctx} do
    assert {:ok, created} = Room.create(%RoomCreateReq{name: "lobby"}, ctx)
    rid = created.room_id

    assert {:ok, _} = Room.join(%RoomOperateReq{room_id: rid}, peer_ctx)
    assert RoomStore.member?(ctx.app_key, rid, peer.user_id)

    assert {:ok, upd} = Room.update(%RoomUpdateReq{room_id: rid, name: "hall"}, ctx)
    assert upd.push.name == "hall"

    assert {:ok, kicked} =
             Room.kick(%RoomKickReq{room_id: rid, member_uids: [peer.user_id]}, ctx)

    assert peer.user_id in kicked.push.member_uids
    refute RoomStore.member?(ctx.app_key, rid, peer.user_id)

    assert {:ok, _} = Room.dismiss(%RoomOperateReq{room_id: rid}, ctx)
    assert {:error, :not_found} = RoomStore.get(ctx.app_key, rid)
  end

  test "非房主不可解散", %{ctx: ctx, peer_ctx: peer_ctx} do
    assert {:ok, created} = Room.create(%RoomCreateReq{name: "x"}, ctx)

    assert {:error, %{code: :group_no_permission}} =
             Room.dismiss(%RoomOperateReq{room_id: created.room_id}, peer_ctx)
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
