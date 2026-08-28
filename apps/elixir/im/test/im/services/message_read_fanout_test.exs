defmodule IM.Services.MessageReadFanoutTest do
  use IM.DataCase, async: true

  alias IM.AuthFixtures
  alias IM.Domain.MessageContext
  alias IM.Group.MetaCache
  alias IM.Services.{Group, Message, Offline}
  alias IM.Stores.{GroupStore, MessageStore}
  alias Pb.Im.Protocol.{ChatMessage, OfflinePullReq}

  test "read_fanout 仅写 bodies，conv 拉取可见" do
    owner = AuthFixtures.create_user!(user_id: "rf_#{System.unique_integer([:positive])}")
    peer = AuthFixtures.create_user!(app_key: owner.app_key)

    ctx = %MessageContext{
      app_key: owner.app_key,
      user_id: owner.user_id,
      device_id: "d1",
      session_id: "s1",
      trace_id: "t",
      node: node()
    }

    {:ok, group} = Group.create(%{"name" => "big", "member_uids" => [peer.user_id]}, ctx)

    {:ok, group} =
      GroupStore.promote_read_fanout(GroupStore.get(owner.app_key, group.group_id) |> elem(1))

    :ok = MetaCache.put(group)

    assert {:ok, sent} =
             Message.send(
               %ChatMessage{
                 chat_type: :CHAT_GROUP,
                 to: group.group_id,
                 msg_type: :MSG_TEXT,
                 content: "rf",
                 client_msg_id: "rf-#{System.unique_integer([:positive])}"
               },
               ctx
             )

    assert [] = MessageStore.list_by_inbox_seq(owner.app_key, peer.user_id, 0, 10)

    peer_ctx = %{ctx | user_id: peer.user_id}

    assert {:ok, resp} =
             Offline.pull(
               %OfflinePullReq{conv_id: "g:#{group.group_id}", cursor: 0, limit: 50},
               peer_ctx
             )

    assert Enum.any?(resp.messages, &(&1.msg_id == sent.message.msg_id))
  end
end
