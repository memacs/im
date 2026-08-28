defmodule IM.Client.Protocol.PrivateMessageTest do
  @moduledoc "单聊：CMD_MSG_SEND/PUSH/ACK、批量 ACK、REST 双通道、cid 幂等。"
  use IM.ClientProtocolCase

  alias IM.Client.{Assertions, Connection, REST}
  alias Pb.Im.Protocol.{ChatMessage, MsgAck, MsgAckBatchUp, MsgSendReq}

  @tag trace_case: "private_message_test/A 发单聊 → B 收 PUSH + 客户端 ACK"
  test "A 发单聊 → B 收 PUSH + 客户端 ACK" do
    %{a: a, b: b} = connect_pair!()
    trace_as!("A")
    cid = unique_id("cm")

    trace!("↑ WS CMD_MSG_SEND", %MsgSendReq{
      message: %ChatMessage{
        from: a.login.user_id,
        to: b.login.user_id,
        chat_type: :CHAT_PRIVATE,
        msg_type: :MSG_TEXT,
        content: "hi-b",
        client_msg_id: cid
      }
    })

    {:ok, ack_packet} =
      Connection.send_message(a.client, %{
        from: a.login.user_id,
        to: b.login.user_id,
        chat_type: :CHAT_PRIVATE,
        content: "hi-b",
        client_msg_id: cid
      })

    trace!("↓ WS CMD_MSG_ACK_DOWN", ack_packet)
    ack = assert_cmd_resp!(ack_packet, :CMD_MSG_ACK_DOWN, MsgAck)

    trace_as!("B")
    push_packet = Assertions.assert_push(b.client) |> elem(1)
    trace!("↓ WS CMD_MSG_PUSH", push_packet)
    push = decode_payload!(push_packet, ChatMessage)
    assert push.msg_id == ack.msg_id

    trace!("↑ WS CMD_MSG_ACK_UP", %MsgAck{
      msg_id: push.msg_id,
      client_msg_id: push.client_msg_id,
      status: :ACK_CLIENT_RECEIVED,
      conv_seq: push.conv_seq
    })

    :ok =
      Connection.ack_client_received(b.client, %{
        msg_id: push.msg_id,
        client_msg_id: push.client_msg_id,
        conv_seq: push.conv_seq
      })
  end

  @tag trace_case: "private_message_test/批量 ACK"
  test "批量 ACK" do
    %{a: a, b: b} = connect_pair!()
    {msg_id, _} = send_private!(a.client, a.login.user_id, b.login.user_id)
    push = await_push_message!(b.client)

    trace_as!("B")
    trace!("↑ WS CMD_MSG_ACK_BATCH_UP", %MsgAckBatchUp{
      acks: [%MsgAck{msg_id: msg_id, client_msg_id: push.client_msg_id, conv_seq: push.conv_seq, status: :ACK_CLIENT_RECEIVED}]
    })

    :ok =
      Connection.ack_batch(b.client, [
        %{msg_id: msg_id, client_msg_id: push.client_msg_id, conv_seq: push.conv_seq}
      ])
  end

  @tag trace_case: "private_message_test/REST 发消息双通道"
  test "REST 发消息双通道" do
    %{a: a, b: b} = connect_pair!()
    trace_as!("A")

    assert {:ok, resp} =
             REST.send_message(base_url(), a.login.token, %{
               to: b.login.user_id,
               content: "rest-path"
             })

    trace_http!("↑ HTTP POST /api/v1/messages", %{to: b.login.user_id, content: "rest-path"}, %{status: 200, body: resp})

    trace_as!("B")
    push_packet = Assertions.assert_push(b.client) |> elem(1)
    trace!("↓ WS CMD_MSG_PUSH", push_packet)
    push = decode_payload!(push_packet, ChatMessage)
    assert push.content == "rest-path"
  end

  @tag trace_case: "private_message_test/client_msg_id 幂等"
  test "client_msg_id 幂等" do
    %{a: a, b: b} = connect_pair!()
    cid = unique_id("idem")
    trace_as!("A")

    trace!("↑ WS CMD_MSG_SEND (1st)", %MsgSendReq{
      message: %ChatMessage{
        from: a.login.user_id,
        to: b.login.user_id,
        chat_type: :CHAT_PRIVATE,
        msg_type: :MSG_TEXT,
        content: "once",
        client_msg_id: cid
      }
    })

    {:ok, p1} =
      Connection.send_message(a.client, %{
        from: a.login.user_id,
        to: b.login.user_id,
        chat_type: :CHAT_PRIVATE,
        content: "once",
        client_msg_id: cid
      })

    ack1 = assert_cmd_resp!(p1, :CMD_MSG_ACK_DOWN, MsgAck)
    trace!("↓ WS CMD_MSG_ACK_DOWN (1st)", p1)

    {:ok, p2} =
      Connection.send_message(a.client, %{
        from: a.login.user_id,
        to: b.login.user_id,
        chat_type: :CHAT_PRIVATE,
        content: "once",
        client_msg_id: cid
      })

    ack2 = assert_cmd_resp!(p2, :CMD_MSG_ACK_DOWN, MsgAck)
    trace!("↓ WS CMD_MSG_ACK_DOWN (2nd 幂等)", p2)
    assert ack1.msg_id == ack2.msg_id
  end
end
