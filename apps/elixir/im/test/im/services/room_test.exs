defmodule IM.Services.RoomTest do
  use IM.DataCase, async: false

  alias IM.AuthFixtures
  alias IM.Domain.MessageContext
  alias IM.Protocol.{Codec, Push}
  alias IM.Room.PubSub, as: RoomPubSub
  alias IM.Services.{Message, Room}
  alias IM.Stores.MessageStore
  alias Pb.Im.Protocol.{ChatMessage, RoomCreateReq, RoomOperateReq}

  setup do
    user = AuthFixtures.create_user!(user_id: "ru_#{System.unique_integer([:positive])}")

    ctx = %MessageContext{
      app_key: user.app_key,
      user_id: user.user_id,
      device_id: "d1",
      session_id: "s1",
      trace_id: "t",
      node: node()
    }

    %{user: user, ctx: ctx}
  end

  test "创建并加入后 PubSub 可收广播", %{ctx: ctx} do
    assert {:ok, created} = Room.create(%RoomCreateReq{name: "lobby"}, ctx)
    assert created.conv_id == "r:#{created.room_id}"

    :ok = RoomPubSub.subscribe(ctx.app_key, created.room_id)

    assert {:ok, _} =
             Room.join(%RoomOperateReq{room_id: created.room_id}, ctx)

    assert {:ok, sent} =
             Message.send(
               %ChatMessage{
                 chat_type: :CHAT_ROOM,
                 to: created.room_id,
                 msg_type: :MSG_TEXT,
                 content: "hi room",
                 client_msg_id: "rm-#{System.unique_integer([:positive])}"
               },
               ctx
             )

    assert sent.ack.status == :ACK_SERVER_RECEIVED
    # 默认不落 inbox
    assert [] = MessageStore.list_by_inbox_seq(ctx.app_key, ctx.user_id, 0, 10)

    {:ok, packet} =
      Push.build(:CMD_MSG_PUSH, sent.message, trace_id: "t", route_key: sent.message.conv_id)

    {:ok, bin} = Codec.encode(packet)

    RoomPubSub.broadcast(ctx.app_key, created.room_id, bin, %{
      exclude_device_id: "other",
      sender_user_id: "x",
      target_users: []
    })

    assert_receive {:im_room_push, ^bin, _meta}, 500
  end

  test "target_users 定向过滤元数据", %{ctx: ctx} do
    assert {:ok, created} = Room.create(%RoomCreateReq{name: "dir"}, ctx)
    :ok = RoomPubSub.subscribe(ctx.app_key, created.room_id)

    RoomPubSub.broadcast(ctx.app_key, created.room_id, <<"x">>, %{
      exclude_device_id: nil,
      sender_user_id: "s",
      target_users: ["only-a"]
    })

    assert_receive {:im_room_push, <<"x">>, meta}, 500
    assert meta.target_users == ["only-a"]
  end
end
