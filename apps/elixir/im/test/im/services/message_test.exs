defmodule IM.Services.MessageTest do
  use IM.DataCase, async: true

  alias IM.AuthFixtures
  alias IM.Connection.Registry
  alias IM.Domain.{Error, MessageContext}
  alias IM.Gateway.CidDedup
  alias IM.Services.Message
  alias IM.Stores.MessageStore
  alias Pb.Im.Protocol.{ChatMessage, MsgAck}

  setup do
    alice = AuthFixtures.create_user!(user_id: "alice_#{System.unique_integer([:positive])}")
    bob = AuthFixtures.create_user!(app_key: alice.app_key, user_id: "bob_#{System.unique_integer([:positive])}")

    ctx = %MessageContext{
      app_key: alice.app_key,
      user_id: alice.user_id,
      device_id: "d-alice-1",
      session_id: "sess-#{System.unique_integer([:positive])}",
      trace_id: "tr-msg",
      platform: :ios,
      node: node()
    }

    %{alice: alice, bob: bob, ctx: ctx}
  end

  test "发送单聊分配 msg_id/conv_seq 并写双方 inbox", %{alice: alice, bob: bob, ctx: ctx} do
    msg = chat(alice.user_id, bob.user_id, "hello", "cid-1")

    assert {:ok, result} = Message.send(msg, ctx)
    assert result.duplicate? == false
    assert result.message.msg_id != ""
    assert result.message.conv_seq == 1
    assert result.ack.status == :ACK_SERVER_RECEIVED
    assert result.message.conv_id == "p:#{min_id(alice.user_id, bob.user_id)}:#{max_id(alice.user_id, bob.user_id)}"

    assert {:ok, _} = MessageStore.get_by_msg_id(alice.app_key, result.message.msg_id)
    rows = MessageStore.list_by_inbox_seq(alice.app_key, alice.user_id, 0, 10)
    assert length(rows) == 1
  end

  test "client_msg_id 幂等返回同一 msg_id", %{alice: alice, bob: bob, ctx: ctx} do
    msg = chat(alice.user_id, bob.user_id, "idem", "same-client")

    assert {:ok, a} = Message.send(msg, ctx)
    assert {:ok, b} = Message.send(msg, %{ctx | session_id: "other-sess"})
    assert a.message.msg_id == b.message.msg_id
    assert b.duplicate? == true
  end

  test "Packet.cid 同连接去重", %{alice: alice, bob: bob, ctx: ctx} do
    msg = chat(alice.user_id, bob.user_id, "c1", "c-a")
    assert {:ok, _} = Message.send(msg, ctx, cid: "packet-1")
    assert {:error, %Error{msg: "duplicate packet cid"}} = Message.send(msg, ctx, cid: "packet-1")
    assert :ok = CidDedup.check(ctx.session_id, "packet-2")
  end

  test "非法 chat_type / conv_id 返回 msg_invalid", %{alice: alice, bob: bob, ctx: ctx} do
    bad = %ChatMessage{
      chat_type: :CHAT_ROOM,
      from: alice.user_id,
      to: bob.user_id,
      content: "x",
      msg_type: :MSG_TEXT
    }

    assert {:error, %Error{code: :msg_invalid}} = Message.send(bad, ctx)

    mismatch = %ChatMessage{
      chat_type: :CHAT_PRIVATE,
      from: alice.user_id,
      to: bob.user_id,
      conv_id: "p:wrong:id",
      content: "x",
      msg_type: :MSG_TEXT,
      client_msg_id: "m1"
    }

    assert {:error, %Error{code: :msg_invalid}} = Message.send(mismatch, ctx)
  end

  test "ACK_UP 转发给发送方 CLIENT_RECEIVED", %{alice: alice, bob: bob, ctx: ctx} do
    assert {:ok, sent} = Message.send(chat(alice.user_id, bob.user_id, "ack", "ack-1"), ctx)

    bob_ctx = %MessageContext{
      app_key: bob.app_key,
      user_id: bob.user_id,
      device_id: "d-bob",
      session_id: "sess-bob",
      trace_id: "tr-ack",
      node: node()
    }

    ack = %MsgAck{
      msg_id: sent.message.msg_id,
      client_msg_id: "ack-1",
      status: :ACK_CLIENT_RECEIVED,
      conv_seq: sent.message.conv_seq
    }

    assert {:ok, %{ack_down: down, sender_user_id: sender}} = Message.ack_up(ack, bob_ctx)
    assert sender == alice.user_id
    assert down.status == :ACK_CLIENT_RECEIVED
  end

  test "多端：排除发送设备推送", %{alice: alice} do
    parent = self()
    sender_dev = spawn_link(fn -> device_loop(parent) end)
    other_dev = spawn_link(fn -> device_loop(parent) end)

    send(sender_dev, {:reg, alice.app_key, alice.user_id, "d-alice-1"})
    send(other_dev, {:reg, alice.app_key, alice.user_id, "d-alice-2"})
    assert_receive :reg_ok, 500
    assert_receive :reg_ok, 500

    msg = %ChatMessage{
      msg_id: "m",
      from: alice.user_id,
      to: "peer",
      conv_id: "p:a:b",
      content: "x",
      client_msg_id: "push-1"
    }

    assert :ok =
             IM.Delivery.Router.push_message(msg, alice.app_key, alice.user_id,
               exclude_device_id: "d-alice-1"
             )

    assert_receive {:pushed, ^other_dev}, 500
    refute_receive {:pushed, ^sender_dev}, 100
  end

  defp device_loop(parent) do
    receive do
      {:reg, app, user, device} ->
        :ok = Registry.register(app, user, device, "ios")
        send(parent, :reg_ok)
        device_loop(parent)

      {:im_push, _bin} ->
        send(parent, {:pushed, self()})
        device_loop(parent)

      {:im_push, _bin, _meta} ->
        send(parent, {:pushed, self()})
        device_loop(parent)
    end
  end

  defp chat(from, to, content, client_msg_id) do
    %ChatMessage{
      chat_type: :CHAT_PRIVATE,
      from: from,
      to: to,
      msg_type: :MSG_TEXT,
      content: content,
      client_msg_id: client_msg_id
    }
  end

  defp min_id(a, b), do: Enum.min([a, b])
  defp max_id(a, b), do: Enum.max([a, b])
end
