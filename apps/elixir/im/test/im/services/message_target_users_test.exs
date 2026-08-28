defmodule IM.Services.MessageTargetUsersTest do
  use IM.DataCase, async: true

  alias IM.AuthFixtures
  alias IM.Domain.MessageContext
  alias IM.Services.{Group, Message}
  alias IM.Stores.MessageStore
  alias Pb.Im.Protocol.ChatMessage

  test "定向群消息仅写目标∪发送方 inbox" do
    owner = AuthFixtures.create_user!(user_id: "to_#{System.unique_integer([:positive])}")

    a =
      AuthFixtures.create_user!(
        app_key: owner.app_key,
        user_id: "ta_#{System.unique_integer([:positive])}"
      )

    b =
      AuthFixtures.create_user!(
        app_key: owner.app_key,
        user_id: "tb_#{System.unique_integer([:positive])}"
      )

    ctx = %MessageContext{
      app_key: owner.app_key,
      user_id: owner.user_id,
      device_id: "d1",
      session_id: "s1",
      trace_id: "t",
      node: node()
    }

    {:ok, group} =
      Group.create(%{"name" => "g", "member_uids" => [a.user_id, b.user_id]}, ctx)

    assert {:ok, result} =
             Message.send(
               %ChatMessage{
                 chat_type: :CHAT_GROUP,
                 to: group.group_id,
                 msg_type: :MSG_TEXT,
                 content: "secret",
                 client_msg_id: "tu-#{System.unique_integer([:positive])}",
                 target_users: [a.user_id]
               },
               ctx
             )

    assert Enum.sort(result.recipient_user_ids) == Enum.sort([owner.user_id, a.user_id])

    assert [_] = MessageStore.list_by_inbox_seq(owner.app_key, owner.user_id, 0, 10)
    assert [_] = MessageStore.list_by_inbox_seq(owner.app_key, a.user_id, 0, 10)
    assert [] = MessageStore.list_by_inbox_seq(owner.app_key, b.user_id, 0, 10)
  end
end
