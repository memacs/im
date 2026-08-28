defmodule IM.Services.OfflineTest do
  use IM.DataCase, async: true

  alias IM.AuthFixtures
  alias IM.Domain.MessageContext
  alias IM.Services.{Message, Offline}
  alias Pb.Im.Protocol.{ChatMessage, OfflinePullReq}

  setup do
    alice = AuthFixtures.create_user!(user_id: "oa_#{System.unique_integer([:positive])}")
    bob = AuthFixtures.create_user!(app_key: alice.app_key, user_id: "ob_#{System.unique_integer([:positive])}")

    ctx = %MessageContext{
      app_key: alice.app_key,
      user_id: alice.user_id,
      device_id: "d1",
      session_id: "s1",
      trace_id: "t",
      node: node()
    }

    %{alice: alice, bob: bob, ctx: ctx}
  end

  test "inbox_seq 全量拉取分页", %{alice: alice, bob: bob, ctx: ctx} do
    for i <- 1..3 do
      msg = %ChatMessage{
        chat_type: :CHAT_PRIVATE,
        from: alice.user_id,
        to: bob.user_id,
        msg_type: :MSG_TEXT,
        content: "m#{i}",
        client_msg_id: "off-#{i}-#{System.unique_integer([:positive])}"
      }

      assert {:ok, _} = Message.send(msg, ctx)
    end

    bob_ctx = %{ctx | user_id: bob.user_id, device_id: "d-bob", session_id: "s-bob"}

    assert {:ok, page1} =
             Offline.pull(%OfflinePullReq{cursor: 0, limit: 2}, bob_ctx)

    assert length(page1.messages) == 2
    assert page1.has_more == true

    assert {:ok, page2} =
             Offline.pull(%OfflinePullReq{cursor: page1.next_cursor, limit: 2}, bob_ctx)

    assert length(page2.messages) == 1
    assert page2.has_more == false
  end

  test "按 conv_id 用 conv_seq 拉取", %{alice: alice, bob: bob, ctx: ctx} do
    assert {:ok, sent} =
             Message.send(
               %ChatMessage{
                 chat_type: :CHAT_PRIVATE,
                 from: alice.user_id,
                 to: bob.user_id,
                 msg_type: :MSG_TEXT,
                 content: "c",
                 client_msg_id: "conv-#{System.unique_integer([:positive])}"
               },
               ctx
             )

    bob_ctx = %{ctx | user_id: bob.user_id}

    assert {:ok, resp} =
             Offline.pull(
               %OfflinePullReq{conv_id: sent.message.conv_id, cursor: 0, limit: 50},
               bob_ctx
             )

    assert length(resp.messages) == 1
    assert hd(resp.messages).conv_seq == sent.message.conv_seq
    assert resp.next_cursor == sent.message.conv_seq
  end
end
