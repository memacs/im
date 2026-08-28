defmodule IM.Application.DispatchTest do
  use IM.DataCase, async: true

  alias IM.Application.Dispatch
  alias IM.AuthFixtures
  alias IM.Domain.MessageContext

  alias Pb.Im.Protocol.{
    ChatMessage,
    CmdType,
    FriendAddReq,
    FriendListReq,
    GroupCreateReq,
    HeartbeatReq,
    MsgSendReq,
    OfflinePullReq,
    RoomCreateReq
  }

  setup do
    alice = AuthFixtures.login!()

    ctx = %MessageContext{
      app_key: alice.app_key,
      user_id: alice.user_id,
      device_id: alice.device_id,
      session_id: "sess",
      trace_id: "dispatch-test",
      node: node()
    }

    %{alice: alice, ctx: ctx}
  end

  test "heartbeat", %{ctx: ctx} do
    assert {:ok, _} =
             Dispatch.execute(CmdType.value(:CMD_HEARTBEAT_REQ), %HeartbeatReq{}, ctx)
  end

  test "msg send private", %{alice: alice, ctx: ctx} do
    bob = AuthFixtures.create_user!(app_key: alice.app_key)

    msg = %ChatMessage{
      client_msg_id: "d-#{System.unique_integer([:positive])}",
      chat_type: :CHAT_PRIVATE,
      from: alice.user_id,
      to: bob.user_id,
      msg_type: :MSG_TEXT,
      content: "hi"
    }

    assert {:ok, %{message: %{msg_id: id}}} =
             Dispatch.execute(CmdType.value(:CMD_MSG_SEND), %MsgSendReq{message: msg}, ctx)

    assert is_binary(id)
  end

  test "offline pull", %{ctx: ctx} do
    assert {:ok, %{messages: _, has_more: _}} =
             Dispatch.execute(
               CmdType.value(:CMD_OFFLINE_PULL_REQ),
               %OfflinePullReq{limit: 10},
               ctx
             )
  end

  test "friend add + list", %{alice: alice, ctx: ctx} do
    bob = AuthFixtures.create_user!(app_key: alice.app_key)

    assert {:ok, %{resp: %{request_id: rid}}} =
             Dispatch.execute(
               CmdType.value(:CMD_FRIEND_ADD_REQ),
               %FriendAddReq{to_user_id: bob.user_id},
               ctx
             )

    assert is_binary(rid)

    assert {:ok, %{resp: _}} =
             Dispatch.execute(CmdType.value(:CMD_FRIEND_LIST_REQ), %FriendListReq{}, ctx)
  end

  test "group + room create", %{ctx: ctx} do
    assert {:ok, %{group_id: gid}} =
             Dispatch.execute(
               CmdType.value(:CMD_GROUP_CREATE_REQ),
               %GroupCreateReq{name: "g-dispatch"},
               ctx
             )

    assert String.starts_with?(gid, "g")

    assert {:ok, %{room_id: rid}} =
             Dispatch.execute(
               CmdType.value(:CMD_ROOM_CREATE_REQ),
               %RoomCreateReq{name: "r-dispatch"},
               ctx
             )

    assert String.starts_with?(rid, "r")
  end

  test "unknown cmd", %{ctx: ctx} do
    assert {:error, %{code: :not_implemented}} = Dispatch.execute(99_999, %{}, ctx)
  end

  test "channel subscribe / publish", %{ctx: ctx} do
    ch = "news:dispatch-#{System.unique_integer([:positive])}"

    assert {:ok, resp} =
             Dispatch.execute(
               CmdType.value(:CMD_CHANNEL_SUBSCRIBE_REQ),
               %{channel_ids: [ch]},
               ctx
             )

    assert ch in resp.subscribed

    assert {:ok, ack} =
             Dispatch.execute(
               CmdType.value(:CMD_CHANNEL_PUBLISH),
               %Pb.Im.Protocol.ChannelPublish{
                 channel_id: ch,
                 content_type: "application/json",
                 payload: "{}",
                 client_event_id: "e1"
               },
               ctx
             )

    assert ack.accepted

    assert {:ok, resp2} =
             Dispatch.execute(
               CmdType.value(:CMD_CHANNEL_UNSUBSCRIBE_REQ),
               %{channel_ids: [ch]},
               ctx
             )

    assert ch in resp2.unsubscribed
  end
end
