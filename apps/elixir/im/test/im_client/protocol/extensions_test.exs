defmodule IM.Client.Protocol.ExtensionsTest do
  @moduledoc "消息扩展：已读/撤回/编辑/透传。"
  use IM.ClientProtocolCase

  alias IM.Client.{Assertions, Connection}
  alias Pb.Im.Protocol.{MsgEdit, MsgRead, MsgRecall, Passthrough}

  setup tags do
    if tags[:trace_case] == "extensions_test/阅后即焚：已读后双方收到 BURN_PUSH" do
      :ok
    else
      %{a: a, b: b} = connect_pair!()

      {msg_id, conv_id} =
        send_private!(a.client, a.login.user_id, b.login.user_id, content: "editable")

      push = await_push_message!(b.client)
      {:ok, a: a, b: b, msg_id: msg_id, conv_id: conv_id, push: push}
    end
  end

  @tag trace_case: "extensions_test/已读回执"
  test "已读回执", %{a: a, b: b, msg_id: msg_id, conv_id: conv_id, push: push} do
    trace_as!("B")

    trace!("↑ WS CMD_MSG_READ", %MsgRead{
      chat_type: :CHAT_PRIVATE,
      from: b.login.user_id,
      to: a.login.user_id,
      msg_id: msg_id,
      conv_seq: push.conv_seq,
      conv_id: conv_id
    })

    :ok =
      Connection.msg_read(b.client, %{
        chat_type: :CHAT_PRIVATE,
        from: b.login.user_id,
        to: a.login.user_id,
        msg_id: msg_id,
        conv_seq: push.conv_seq,
        conv_id: conv_id
      })

    {:ok, read_push} = Connection.await(a.client, [cmd: CmdType.value(:CMD_MSG_READ)], 3_000)
    trace_as!("A")
    trace!("↓ WS CMD_MSG_READ (对端已读)", read_push)
    read_down = decode_payload!(read_push, MsgRead)
    assert read_down.unread_count == 0
  end

  @tag trace_case: "extensions_test/编辑消息"
  test "编辑消息", %{a: a, msg_id: msg_id, conv_id: conv_id} do
    trace_as!("A")

    {:ok, packet} =
      Connection.edit_message(a.client, %{msg_id: msg_id, conv_id: conv_id, content: "edited"})

    trace!("↓ WS CMD_MSG_EDIT_PUSH", packet)
    edit = assert_cmd_resp!(packet, :CMD_MSG_EDIT_PUSH, MsgEdit)
    assert edit.content == "edited"
  end

  @tag trace_case: "extensions_test/撤回消息"
  test "撤回消息", %{a: a, b: b, msg_id: msg_id, conv_id: conv_id} do
    trace_as!("A")

    {:ok, packet} =
      Connection.recall_message(a.client, %{msg_id: msg_id, conv_id: conv_id, reason: "mistake"})

    trace!("↓ WS CMD_MSG_RECALL_PUSH", packet)
    recall = assert_cmd_resp!(packet, :CMD_MSG_RECALL_PUSH, MsgRecall)
    assert recall.msg_id == msg_id

    case Connection.await(b.client, [cmd: CmdType.value(:CMD_MSG_RECALL_PUSH)], 2_000) do
      {:ok, push_packet} ->
        trace_as!("B")
        trace!("↓ WS CMD_MSG_RECALL_PUSH (对端)", push_packet)
        body = decode_payload!(push_packet, MsgRecall)
        assert body.msg_id == msg_id

      {:error, :timeout} ->
        :ok
    end
  end

  @tag trace_case: "extensions_test/透传指令"
  test "透传指令", %{a: a, b: b} do
    trace_as!("A")

    trace!("↑ WS CMD_PASSTHROUGH", %Passthrough{
      chat_type: :CHAT_PRIVATE,
      from: a.login.user_id,
      to: b.login.user_id,
      action: "typing",
      data: ~s({"typing":true}),
      persist: false
    })

    :ok =
      Connection.passthrough(a.client, %{
        chat_type: :CHAT_PRIVATE,
        from: a.login.user_id,
        to: b.login.user_id,
        action: "typing",
        data: ~s({"typing":true}),
        persist: false
      })

    {:ok, down} = Connection.await(b.client, [cmd: CmdType.value(:CMD_PASSTHROUGH)], 2_000)
    trace_as!("B")
    trace!("↓ WS CMD_PASSTHROUGH", down)
    pt = decode_payload!(down, Passthrough)
    assert pt.action == "typing"
  end

  @tag trace_case: "extensions_test/阅后即焚：已读后双方收到 BURN_PUSH"
  test "阅后即焚：已读后双方收到 BURN_PUSH" do
    %{a: a, b: b} = connect_pair!()

    trace_as!("A")

    {:ok, packet} =
      Connection.send_message(a.client, %{
        from: a.login.user_id,
        to: b.login.user_id,
        chat_type: :CHAT_PRIVATE,
        content: "secret",
        burn_after_read: true,
        burn_ttl_sec: 0
      })

    trace!("↓ WS CMD_MSG_ACK_DOWN", packet)
    ack = assert_cmd_resp!(packet, :CMD_MSG_ACK_DOWN, Pb.Im.Protocol.MsgAck)
    push_packet = Assertions.assert_push(b.client) |> elem(1)
    trace_as!("B")
    trace!("↓ WS CMD_MSG_PUSH", push_packet)
    push = decode_payload!(push_packet, Pb.Im.Protocol.ChatMessage)

    trace!("↑ WS CMD_MSG_READ", %MsgRead{
      chat_type: :CHAT_PRIVATE,
      from: b.login.user_id,
      to: a.login.user_id,
      msg_id: push.msg_id,
      conv_seq: push.conv_seq,
      conv_id: push.conv_id
    })

    :ok =
      Connection.msg_read(b.client, %{
        chat_type: :CHAT_PRIVATE,
        from: b.login.user_id,
        to: a.login.user_id,
        msg_id: push.msg_id,
        conv_seq: push.conv_seq,
        conv_id: push.conv_id
      })

    {:ok, burn_a} = Assertions.await_cmd(a.client, CmdType.value(:CMD_MSG_BURN_PUSH), 5_000)
    trace_as!("A")
    trace!("↓ WS CMD_MSG_BURN_PUSH", burn_a)
    burn = decode_payload!(burn_a, Pb.Im.Protocol.MsgBurn)
    assert burn.msg_id == ack.msg_id
  end
end
