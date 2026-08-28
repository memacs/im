defmodule IM.Services.UnreadCountTest do
  use IM.DataCase, async: true

  alias IM.AuthFixtures
  alias IM.Domain.MessageContext
  alias IM.Services.Message
  alias IM.Stores.ConversationStore
  alias Pb.Im.Protocol.ChatMessage

  test "单聊发送后对端 unread +1，发送方不增" do
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
                 content: "hi",
                 client_msg_id: "un-#{System.unique_integer([:positive])}"
               },
               ctx
             )

    assert ConversationStore.get_unread(alice.app_key, bob.user_id, sent.message.conv_id) == 1
    assert ConversationStore.get_unread(alice.app_key, alice.user_id, sent.message.conv_id) == 0
  end
end
