defmodule IM.Services.MessageGroupTest do
  use IM.DataCase, async: true

  alias IM.AuthFixtures
  alias IM.Domain.{Error, MessageContext}
  alias IM.Services.{Group, Message, Offline}
  alias IM.Stores.MessageStore
  alias Pb.Im.Protocol.{ChatMessage, OfflinePullReq}

  setup do
    owner = AuthFixtures.create_user!(user_id: "go_#{System.unique_integer([:positive])}")
    m2 = AuthFixtures.create_user!(app_key: owner.app_key, user_id: "g2_#{System.unique_integer([:positive])}")
    m3 = AuthFixtures.create_user!(app_key: owner.app_key, user_id: "g3_#{System.unique_integer([:positive])}")

    ctx = %MessageContext{
      app_key: owner.app_key,
      user_id: owner.user_id,
      device_id: "d-owner",
      session_id: "s-owner",
      trace_id: "tg",
      node: node()
    }

    {:ok, group} =
      Group.create(%{"name" => "team", "member_uids" => [m2.user_id, m3.user_id]}, ctx)

    %{owner: owner, m2: m2, m3: m3, ctx: ctx, group: group}
  end

  test "群消息写扩散到全体成员 inbox", %{owner: owner, m2: m2, m3: m3, ctx: ctx, group: group} do
    msg = %ChatMessage{
      chat_type: :CHAT_GROUP,
      from: owner.user_id,
      to: group.group_id,
      msg_type: :MSG_TEXT,
      content: "hello group",
      client_msg_id: "gmsg-#{System.unique_integer([:positive])}"
    }

    assert {:ok, result} = Message.send(msg, ctx)
    assert result.message.conv_id == "g:#{group.group_id}"
    assert result.message.chat_type == :CHAT_GROUP
    assert Enum.sort(result.recipient_user_ids) == Enum.sort([owner.user_id, m2.user_id, m3.user_id])

    for uid <- [owner.user_id, m2.user_id, m3.user_id] do
      rows = MessageStore.list_by_inbox_seq(owner.app_key, uid, 0, 10)
      assert Enum.any?(rows, fn r -> r.body.msg_id == result.message.msg_id end)
    end
  end

  test "禁言成员无法发群消息", %{owner: owner, m2: m2, ctx: ctx, group: group} do
    until = System.system_time(:millisecond) + 60_000
    assert {:ok, _} = Group.mute_member(group.group_id, m2.user_id, until, ctx)

    m2_ctx = %{ctx | user_id: m2.user_id, device_id: "d-m2", session_id: "s-m2"}

    msg = %ChatMessage{
      chat_type: :CHAT_GROUP,
      to: group.group_id,
      msg_type: :MSG_TEXT,
      content: "muted",
      client_msg_id: "mute-#{System.unique_integer([:positive])}"
    }

    assert {:error, %Error{code: :group_no_permission}} = Message.send(msg, m2_ctx)

    # 群主仍可发
    assert {:ok, _} =
             Message.send(
               %ChatMessage{
                 chat_type: :CHAT_GROUP,
                 to: group.group_id,
                 msg_type: :MSG_TEXT,
                 content: "owner ok",
                 client_msg_id: "own-#{System.unique_integer([:positive])}"
               },
               ctx
             )

    _ = owner
  end

  test "非成员发送失败", %{m2: m2, group: group} do
    outsider = AuthFixtures.create_user!(app_key: m2.app_key)

    ctx = %MessageContext{
      app_key: outsider.app_key,
      user_id: outsider.user_id,
      device_id: "d-out",
      session_id: "s-out",
      trace_id: "t",
      node: node()
    }

    msg = %ChatMessage{
      chat_type: :CHAT_GROUP,
      to: group.group_id,
      msg_type: :MSG_TEXT,
      content: "nope",
      client_msg_id: "x-#{System.unique_integer([:positive])}"
    }

    assert {:error, %Error{code: :group_not_member}} = Message.send(msg, ctx)
  end

  test "离线拉取可 JOIN 群消息", %{owner: owner, m2: m2, ctx: ctx, group: group} do
    assert {:ok, sent} =
             Message.send(
               %ChatMessage{
                 chat_type: :CHAT_GROUP,
                 to: group.group_id,
                 msg_type: :MSG_TEXT,
                 content: "pullme",
                 client_msg_id: "pull-#{System.unique_integer([:positive])}"
               },
               ctx
             )

    bob_ctx = %{ctx | user_id: m2.user_id, device_id: "d2", session_id: "s2"}

    assert {:ok, resp} = Offline.pull(%OfflinePullReq{cursor: 0, limit: 50}, bob_ctx)
    assert Enum.any?(resp.messages, &(&1.msg_id == sent.message.msg_id))

    assert {:ok, by_conv} =
             Offline.pull(
               %OfflinePullReq{conv_id: "g:#{group.group_id}", cursor: 0, limit: 50},
               bob_ctx
             )

    refute by_conv.messages == []
    assert hd(by_conv.messages).conv_id == "g:#{group.group_id}"
    _ = owner
  end
end
