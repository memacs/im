defmodule IM.Services.MessageReadTest do
  use IM.DataCase, async: true

  alias IM.AuthFixtures
  alias IM.Domain.MessageContext
  alias IM.Services.{Message, MessageRead}
  alias IM.Stores.ConversationStore
  alias IM.Stores.ConversationStore
  alias Pb.Im.Protocol.{ChatMessage, MsgRead}

  test "CMD_MSG_READ 下行携带已读后该会话未读数（应为 0）" do
    alice = AuthFixtures.create_user!()
    bob = AuthFixtures.create_user!(app_key: alice.app_key)

    alice_ctx = %MessageContext{
      app_key: alice.app_key,
      user_id: alice.user_id,
      device_id: "d-a",
      session_id: "s",
      trace_id: "t",
      node: node()
    }

    bob_ctx = %{alice_ctx | user_id: bob.user_id, device_id: "d-b"}

    assert {:ok, sent} =
             Message.send(
               %ChatMessage{
                 chat_type: :CHAT_PRIVATE,
                 to: bob.user_id,
                 msg_type: :MSG_TEXT,
                 content: "hi",
                 client_msg_id: "mr-#{System.unique_integer([:positive])}"
               },
               alice_ctx
             )

    assert ConversationStore.get_unread(alice.app_key, bob.user_id, sent.message.conv_id) == 1

    assert {:ok, %{read: down}} =
             MessageRead.mark(
               %MsgRead{
                 chat_type: :CHAT_PRIVATE,
                 to: alice.user_id,
                 conv_id: sent.message.conv_id,
                 conv_seq: sent.message.conv_seq
               },
               bob_ctx
             )

    assert down.unread_count == 0
    assert ConversationStore.get_unread(alice.app_key, bob.user_id, sent.message.conv_id) == 0
  end

  test "发消息后更新会话 last_msg 元数据" do
    alice = AuthFixtures.create_user!()
    bob = AuthFixtures.create_user!(app_key: alice.app_key)

    ctx = %MessageContext{
      app_key: alice.app_key,
      user_id: alice.user_id,
      device_id: "d",
      session_id: "s",
      trace_id: "t",
      node: node()
    }

    assert {:ok, sent} =
             Message.send(
               %ChatMessage{
                 chat_type: :CHAT_PRIVATE,
                 to: bob.user_id,
                 msg_type: :MSG_TEXT,
                 content: "meta",
                 client_msg_id: "lm-#{System.unique_integer([:positive])}"
               },
               ctx
             )

    row =
      IM.Repo.get_by!(IM.Schemas.Conversation,
        app_key: alice.app_key,
        user_id: bob.user_id,
        conv_id: sent.message.conv_id
      )

    assert row.last_msg_id == sent.message.msg_id
    assert row.last_msg_time == sent.message.server_time
    assert row.last_msg_seq == sent.message.conv_seq

    sender_row =
      IM.Repo.get_by!(IM.Schemas.Conversation,
        app_key: alice.app_key,
        user_id: alice.user_id,
        conv_id: sent.message.conv_id
      )

    assert sender_row.last_msg_id == sent.message.msg_id
    assert sender_row.peer_id == bob.user_id
    assert ConversationStore.get_unread(alice.app_key, alice.user_id, sent.message.conv_id) == 0
  end
end
