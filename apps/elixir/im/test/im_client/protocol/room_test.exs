defmodule IM.Client.Protocol.RoomTest do
  @moduledoc "聊天室：创建/加入/更新/踢人/离开/解散 + 室消息。"
  use IM.ClientProtocolCase

  alias IM.Client.{Assertions, Connection}
  alias Pb.Im.Protocol.{RoomCreateResp, RoomKickReq, RoomOperateReq, RoomUpdateReq}

  @tag trace_case: "room_test/聊天室生命周期与广播"
  test "聊天室生命周期与广播" do
    %{a: owner, b: guest} = connect_pair!()
    room_id = unique_id("room")

    trace_as!("owner")
    {:ok, create_packet} =
      Connection.create_room(owner.client, %{room_id: room_id, name: "lobby"})

    trace!("↓ WS CMD_ROOM_CREATE_RESP", create_packet)
    created = assert_cmd_resp!(create_packet, :CMD_ROOM_CREATE_RESP, RoomCreateResp)
    assert created.room_id == room_id

    trace_as!("guest")
    {:ok, join_packet} = Connection.join_room(guest.client, room_id)
    trace!("↓ WS CMD_ROOM_JOIN_PUSH", join_packet)

    trace_as!("owner")
    trace!("↑ WS CMD_ROOM_UPDATE_REQ", %RoomUpdateReq{room_id: room_id, name: "lobby-2"})

    {:ok, update_packet} =
      Connection.request(owner.client, :CMD_ROOM_UPDATE_REQ, %RoomUpdateReq{
        room_id: room_id,
        name: "lobby-2"
      })

    trace!("↓ WS CMD_ROOM_UPDATE_PUSH", update_packet)

    {:ok, msg_packet} =
      Connection.send_message(owner.client, %{
        from: owner.login.user_id,
        to: room_id,
        chat_type: :CHAT_ROOM,
        content: "room-msg",
        route_key: room_id
      })

    trace!("↓ WS CMD_MSG_ACK_DOWN", msg_packet)
    assert_cmd_resp!(msg_packet, :CMD_MSG_ACK_DOWN, Pb.Im.Protocol.MsgAck)

    trace_as!("guest")
    push_packet = Assertions.assert_push(guest.client) |> elem(1)
    trace!("↓ WS CMD_MSG_PUSH", push_packet)
    push = decode_payload!(push_packet, Pb.Im.Protocol.ChatMessage)
    assert push.content == "room-msg"

    trace_as!("owner")
    trace!("↑ WS CMD_ROOM_KICK_REQ", %RoomKickReq{
      room_id: room_id,
      member_uids: [guest.login.user_id],
      reason: "test"
    })

    {:ok, kick_packet} =
      Connection.request(owner.client, :CMD_ROOM_KICK_REQ, %RoomKickReq{
        room_id: room_id,
        member_uids: [guest.login.user_id],
        reason: "test"
      })

    trace!("↓ WS CMD_ROOM_KICK_PUSH", kick_packet)

    trace_as!("guest")
    {:ok, join2} = Connection.join_room(guest.client, room_id)
    trace!("↓ WS CMD_ROOM_JOIN_PUSH (rejoin)", join2)

    {:ok, leave_packet} = Connection.leave_room(guest.client, room_id)
    trace!("↓ WS CMD_ROOM_LEAVE_PUSH", leave_packet)

    trace_as!("owner")
    trace!("↑ WS CMD_ROOM_DISMISS_REQ", %RoomOperateReq{room_id: room_id})

    {:ok, dismiss_packet} =
      Connection.request(owner.client, :CMD_ROOM_DISMISS_REQ, %RoomOperateReq{room_id: room_id})

    trace!("↓ WS CMD_ROOM_DISMISS_PUSH", dismiss_packet)
  end
end
