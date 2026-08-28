defmodule IM.Client.Protocol.ConversationTest do
  @moduledoc "会话列表 REST、未读数与已读回执同步。"
  use IM.ClientProtocolCase

  alias IM.Client.{Assertions, Connection, REST}
  alias Pb.Im.Protocol.{ChatMessage, MsgRead, MsgSendReq}

  @tag trace_case: "conversation_test/REST 会话列表未读与已读同步"
  test "REST 会话列表未读与已读同步" do
    %{a: a, b: b} = connect_pair!()
    cid = unique_id("conv")

    trace_as!("A")
    trace!("↑ WS CMD_MSG_SEND", %MsgSendReq{
      message: %ChatMessage{
        from: a.login.user_id,
        to: b.login.user_id,
        chat_type: :CHAT_PRIVATE,
        msg_type: :MSG_TEXT,
        content: "list-preview",
        client_msg_id: cid
      }
    })

    {:ok, ack_packet} =
      Connection.send_message(a.client, %{
        from: a.login.user_id,
        to: b.login.user_id,
        chat_type: :CHAT_PRIVATE,
        content: "list-preview",
        client_msg_id: cid
      })

    trace!("↓ WS CMD_MSG_ACK_DOWN", ack_packet)
    ack = assert_cmd_resp!(ack_packet, :CMD_MSG_ACK_DOWN, Pb.Im.Protocol.MsgAck)
    conv_id = IM.Domain.ConvId.private(a.login.user_id, b.login.user_id)

    trace_as!("B")
    push_packet = Assertions.assert_push(b.client) |> elem(1)
    trace!("↓ WS CMD_MSG_PUSH", push_packet)
    push = decode_payload!(push_packet, ChatMessage)
    assert push.msg_id == ack.msg_id

    assert {:ok, list_before} = REST.list_conversations(base_url(), b.login.token, limit: 20)

    trace_http!(
      "↑ HTTP GET /api/v1/conversations",
      %{limit: 20},
      %{status: 200, body: list_before}
    )

    assert list_before["total_unread"] == 1

    conv_before =
      Enum.find(list_before["conversations"], &(&1["conv_id"] == conv_id))

    assert conv_before["unread_count"] == 1
    assert conv_before["last_msg_preview"] == "list-preview"

    trace!("↑ WS CMD_MSG_READ", %MsgRead{
      chat_type: :CHAT_PRIVATE,
      from: b.login.user_id,
      to: a.login.user_id,
      msg_id: push.msg_id,
      conv_seq: push.conv_seq,
      conv_id: conv_id
    })

    :ok =
      Connection.msg_read(b.client, %{
        chat_type: :CHAT_PRIVATE,
        from: b.login.user_id,
        to: a.login.user_id,
        msg_id: push.msg_id,
        conv_seq: push.conv_seq,
        conv_id: conv_id
      })

    {:ok, read_push} = Connection.await(a.client, [cmd: CmdType.value(:CMD_MSG_READ)], 3_000)
    trace_as!("A")
    trace!("↓ WS CMD_MSG_READ (对端已读)", read_push)
    read_down = decode_payload!(read_push, MsgRead)
    assert read_down.unread_count == 0

    assert {:ok, list_after} = REST.list_conversations(base_url(), b.login.token, limit: 20)

    trace_http!(
      "↑ HTTP GET /api/v1/conversations (after read)",
      %{limit: 20},
      %{status: 200, body: list_after}
    )

    assert list_after["total_unread"] == 0

    conv_after =
      Enum.find(list_after["conversations"], &(&1["conv_id"] == conv_id))

    assert conv_after["unread_count"] == 0
  end

  @tag trace_case: "conversation_test/群聊会话列表未读"
  test "群聊会话列表未读" do
    %{a: owner, b: member} = connect_pair!()
    group_id = unique_id("gc")

    trace_as!("owner")
    {:ok, create_packet} =
      Connection.create_group(owner.client, %{
        group_id: group_id,
        name: "conv-g",
        member_uids: [member.login.user_id]
      })

    trace!("↓ WS CMD_GROUP_CREATE_RESP", create_packet)
    created = assert_cmd_resp!(create_packet, :CMD_GROUP_CREATE_RESP, Pb.Im.Protocol.GroupCreateResp)

    {:ok, msg_packet} =
      Connection.send_message(owner.client, %{
        from: owner.login.user_id,
        to: group_id,
        chat_type: :CHAT_GROUP,
        content: "group-unread",
        client_msg_id: unique_id("gcm")
      })

    trace!("↓ WS CMD_MSG_ACK_DOWN", msg_packet)

    assert {:ok, list} = REST.list_conversations(base_url(), member.login.token, limit: 20)

    trace_http!(
      "↑ HTTP GET /api/v1/conversations (group)",
      %{limit: 20},
      %{status: 200, body: list}
    )

    conv =
      Enum.find(list["conversations"], &(&1["conv_id"] == created.conv_id))

    assert conv["unread_count"] >= 1
    assert conv["last_msg_preview"] == "group-unread"
  end
end
