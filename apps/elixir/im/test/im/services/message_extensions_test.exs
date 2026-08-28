defmodule IM.Services.MessageExtensionsTest do
  use IM.DataCase, async: false

  alias IM.AuthFixtures
  alias IM.Domain.{Error, MessageContext}
  alias IM.Jobs.TtlPurge
  alias IM.Services.{Message, MessageEdit, MessageRead, MessageRecall, Group}
  alias IM.Services.Passthrough, as: PassthroughService
  alias IM.Stores.MessageStore
  alias IM.Stores.PassthroughStore
  alias Pb.Im.Protocol.{ChatMessage, MsgAck, MsgAckBatchUp, MsgEdit, MsgRead, MsgRecall}
  alias Pb.Im.Protocol.Passthrough, as: PassthroughMsg

  setup do
    alice = AuthFixtures.create_user!(user_id: "ea_#{System.unique_integer([:positive])}")
    bob = AuthFixtures.create_user!(app_key: alice.app_key, user_id: "eb_#{System.unique_integer([:positive])}")

    alice_ctx = ctx(alice, "d-a")
    bob_ctx = ctx(bob, "d-b")
    %{alice: alice, bob: bob, alice_ctx: alice_ctx, bob_ctx: bob_ctx}
  end

  test "批量 ACK", %{alice: alice, bob: bob, alice_ctx: alice_ctx, bob_ctx: bob_ctx} do
    assert {:ok, s1} = send_text(alice_ctx, bob.user_id, "a")
    assert {:ok, s2} = send_text(alice_ctx, bob.user_id, "b")

    batch = %MsgAckBatchUp{
      acks: [
        %MsgAck{msg_id: s1.message.msg_id, status: :ACK_CLIENT_RECEIVED},
        %MsgAck{msg_id: s2.message.msg_id, status: :ACK_CLIENT_RECEIVED}
      ]
    }

    assert {:ok, %{batches: [{sender, down}]}} = Message.ack_batch_up(batch, bob_ctx)
    assert sender == alice.user_id
    assert length(down.acks) == 2
  end

  test "撤回与超窗", %{alice_ctx: alice_ctx, bob: bob} do
    assert {:ok, sent} = send_text(alice_ctx, bob.user_id, "r")

    assert {:ok, %{recall: push}} =
             MessageRecall.recall(%MsgRecall{msg_id: sent.message.msg_id}, alice_ctx)

    assert push.msg_id == sent.message.msg_id
    assert {:ok, body} = MessageStore.get_by_msg_id(alice_ctx.app_key, sent.message.msg_id)
    assert body.recalled

    # 超窗：把 server_time 改旧
    body
    |> IM.Schemas.MessageBody.changeset(%{server_time: 1})
    |> IM.Repo.update!()

    assert {:ok, sent2} = send_text(alice_ctx, bob.user_id, "r2")

    sent2_body =
      elem(MessageStore.get_by_msg_id(alice_ctx.app_key, sent2.message.msg_id), 1)
      |> IM.Schemas.MessageBody.changeset(%{server_time: 1})
      |> IM.Repo.update!()

    assert {:error, %Error{code: :msg_recall_denied}} =
             MessageRecall.recall(%MsgRecall{msg_id: sent2_body.msg_id}, alice_ctx)
  end

  test "群管理员可撤回成员消息", %{alice: alice, bob: bob, alice_ctx: alice_ctx} do
    charlie =
      AuthFixtures.create_user!(app_key: alice.app_key, user_id: "ec_#{System.unique_integer([:positive])}")

    bob_ctx = ctx(bob, "d-b-recall")
    charlie_ctx = ctx(charlie, "d-c-recall")

    assert {:ok, group} =
             Group.create(
               %{"name" => "recall-g", "member_uids" => [bob.user_id, charlie.user_id]},
               alice_ctx
             )

    assert {:ok, sent} =
             Message.send(
               %ChatMessage{
                 chat_type: :CHAT_GROUP,
                 from: bob.user_id,
                 to: group.group_id,
                 msg_type: :MSG_TEXT,
                 content: "member msg",
                 client_msg_id: "gm-#{System.unique_integer([:positive])}"
               },
               bob_ctx
             )

    assert {:ok, %{recall: push}} =
             MessageRecall.recall(
               %MsgRecall{msg_id: sent.message.msg_id, reason: "admin cleanup"},
               alice_ctx
             )

    assert push.msg_id == sent.message.msg_id
    assert push.reason == "admin cleanup"
    assert {:ok, body} = MessageStore.get_by_msg_id(alice.app_key, sent.message.msg_id)
    assert body.recalled

    assert {:error, %Error{code: :msg_recall_denied}} =
             MessageRecall.recall(%MsgRecall{msg_id: sent.message.msg_id}, charlie_ctx)
  end

  test "编辑递增 edit_version", %{alice_ctx: alice_ctx, bob: bob} do
    assert {:ok, sent} = send_text(alice_ctx, bob.user_id, "e")

    assert {:ok, %{edit: e1}} =
             MessageEdit.edit(%MsgEdit{msg_id: sent.message.msg_id, content: "e2"}, alice_ctx)

    assert e1.edit_version == 1

    assert {:ok, %{edit: e2}} =
             MessageEdit.edit(%MsgEdit{msg_id: sent.message.msg_id, content: "e3"}, alice_ctx)

    assert e2.edit_version == 2
  end

  test "已读触发阅后即焚", %{alice: alice, bob: bob, alice_ctx: alice_ctx, bob_ctx: bob_ctx} do
    assert {:ok, sent} =
             Message.send(
               %ChatMessage{
                 chat_type: :CHAT_PRIVATE,
                 to: bob.user_id,
                 msg_type: :MSG_TEXT,
                 content: "secret",
                 client_msg_id: "burn-#{System.unique_integer([:positive])}",
                 burn_after_read: true,
                 burn_ttl_sec: 0
               },
               alice_ctx
             )

    assert {:ok, _} =
             MessageRead.mark(
               %MsgRead{
                 chat_type: :CHAT_PRIVATE,
                 to: alice.user_id,
                 conv_id: sent.message.conv_id,
                 conv_seq: sent.message.conv_seq
               },
               bob_ctx
             )

    assert {:ok, b} = MessageStore.get_by_msg_id(alice.app_key, sent.message.msg_id)
    assert b.burned == true
    assert b.content == <<>>
  end

  test "透传 persist 与流式 action", %{alice_ctx: alice_ctx, bob: bob} do
    assert {:ok, %{stream?: true, recipient_user_ids: ids}} =
             PassthroughService.send(
               %PassthroughMsg{
                 chat_type: :CHAT_PRIVATE,
                 to: bob.user_id,
                 action: "stream_start",
                 data: Jason.encode!(%{stream_id: "s1"}),
                 persist: false
               },
               alice_ctx
             )

    assert bob.user_id in ids

    assert {:ok, _} =
             PassthroughService.send(
               %PassthroughMsg{
                 chat_type: :CHAT_PRIVATE,
                 to: bob.user_id,
                 action: "ping",
                 data: "x",
                 persist: true,
                 ttl_sec: 60
               },
               alice_ctx
             )

    assert [_] = PassthroughStore.list_pending(alice_ctx.app_key, bob.user_id)
  end

  test "TTL purge 分批删除过期", %{alice_ctx: alice_ctx, bob: bob} do
    assert {:ok, sent} = send_text(alice_ctx, bob.user_id, "old")

    {:ok, body} = MessageStore.get_by_msg_id(alice_ctx.app_key, sent.message.msg_id)
    old = DateTime.utc_now() |> DateTime.add(-10 * 86_400, :second) |> DateTime.truncate(:microsecond)

    body
    |> IM.Schemas.MessageBody.changeset(%{})
    |> Ecto.Changeset.force_change(:inserted_at, old)
    |> IM.Repo.update!()

    result = TtlPurge.run_once(app_key: alice_ctx.app_key, msg_ttl_days: 7, batch: 100)
    assert result.chat.bodies >= 1
    assert {:error, :not_found} = MessageStore.get_by_msg_id(alice_ctx.app_key, sent.message.msg_id)
  end

  defp send_text(ctx, to, content) do
    Message.send(
      %ChatMessage{
        chat_type: :CHAT_PRIVATE,
        to: to,
        msg_type: :MSG_TEXT,
        content: content,
        client_msg_id: "c-#{System.unique_integer([:positive])}"
      },
      ctx
    )
  end

  defp ctx(user, device) do
    %MessageContext{
      app_key: user.app_key,
      user_id: user.user_id,
      device_id: device,
      session_id: "s-#{device}",
      trace_id: "t",
      node: node()
    }
  end

end
