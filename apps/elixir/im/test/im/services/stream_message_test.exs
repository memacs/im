defmodule IM.Services.StreamMessageTest do
  use IM.DataCase, async: false

  alias IM.AuthFixtures
  alias IM.Domain.{Error, MessageContext}
  alias IM.Services.{Message, Offline, StreamManager}
  alias IM.Stores.MessageStore
  alias Pb.Im.Protocol.{ChatMessage, OfflinePullReq, StreamContent}

  setup do
    StreamManager.reset()

    alice = AuthFixtures.create_user!(user_id: "sa_#{System.unique_integer([:positive])}")

    bob =
      AuthFixtures.create_user!(
        app_key: alice.app_key,
        user_id: "sb_#{System.unique_integer([:positive])}"
      )

    alice_ctx = %MessageContext{
      app_key: alice.app_key,
      user_id: alice.user_id,
      device_id: "d-a",
      session_id: "s-a",
      trace_id: "stream-t",
      node: node()
    }

    bob_ctx = %{alice_ctx | user_id: bob.user_id, device_id: "d-b", session_id: "s-b"}
    %{alice: alice, bob: bob, alice_ctx: alice_ctx, bob_ctx: bob_ctx}
  end

  test "MSG_STREAM 块落库并可离线拉取", %{alice: alice, bob: bob, alice_ctx: alice_ctx, bob_ctx: bob_ctx} do
    stream_id = "st-#{System.unique_integer([:positive])}"

    assert {:ok, start} =
             send_stream(alice_ctx, bob.user_id, stream_id, :STREAM_STATUS_START, 1, "")

    assert start.message.msg_type == :MSG_STREAM

    assert {:ok, body} = MessageStore.get_by_msg_id(alice.app_key, start.message.msg_id)
    assert body.msg_type == 8

    assert {:ok, _} =
             send_stream(alice_ctx, bob.user_id, stream_id, :STREAM_STATUS_ONGOING, 2, "Hel")

    assert {:ok, _} =
             send_stream(alice_ctx, bob.user_id, stream_id, :STREAM_STATUS_ONGOING, 3, "lo")

    assert {:ok, _} =
             send_stream(alice_ctx, bob.user_id, stream_id, :STREAM_STATUS_END, 4, "")

    assert {:ok, pull} =
             Offline.pull(%OfflinePullReq{conv_id: start.message.conv_id, limit: 20}, bob_ctx)

    streams = Enum.filter(pull.messages, &(&1.msg_type == :MSG_STREAM))
    assert length(streams) == 4

    decoded =
      streams
      |> Enum.map(fn m -> StreamContent.decode(m.content) end)
      |> Enum.sort_by(& &1.sequence)

    assert Enum.map(decoded, & &1.chunk) == ["", "Hel", "lo", ""]
    assert Enum.at(decoded, -1).status == :STREAM_STATUS_END
  end

  test "已结束流拒绝后续 ONGOING", %{alice_ctx: alice_ctx, bob: bob} do
    stream_id = "st-end-#{System.unique_integer([:positive])}"

    assert {:ok, _} =
             send_stream(alice_ctx, bob.user_id, stream_id, :STREAM_STATUS_START, 1, "")

    assert {:ok, _} =
             send_stream(alice_ctx, bob.user_id, stream_id, :STREAM_STATUS_END, 2, "")

    assert {:error, %Error{code: :msg_invalid}} =
             send_stream(alice_ctx, bob.user_id, stream_id, :STREAM_STATUS_ONGOING, 3, "x")
  end

  test "缺少 stream_id 拒绝", %{alice_ctx: alice_ctx, bob: bob} do
    assert {:error, %Error{code: :msg_invalid}} =
             send_stream(alice_ctx, bob.user_id, "", :STREAM_STATUS_START, 1, "x")
  end

  test "StreamManager 汇总文本", %{alice_ctx: alice_ctx, bob: bob} do
    stream_id = "st-join-#{System.unique_integer([:positive])}"

    assert {:ok, _} =
             send_stream(alice_ctx, bob.user_id, stream_id, :STREAM_STATUS_START, 1, "")

    assert {:ok, _} =
             send_stream(alice_ctx, bob.user_id, stream_id, :STREAM_STATUS_ONGOING, 2, "A")

    assert {:ok, _} =
             send_stream(alice_ctx, bob.user_id, stream_id, :STREAM_STATUS_ONGOING, 3, "B")

    assert {:ok, text} = StreamManager.assembled_text(alice_ctx.app_key, stream_id)
    assert text == "AB"
  end

  defp send_stream(ctx, to, stream_id, status, sequence, chunk) do
    sc = %StreamContent{
      stream_id: stream_id,
      status: status,
      sequence: sequence,
      chunk: chunk,
      content_type: "text/plain"
    }

    Message.send(
      %ChatMessage{
        chat_type: :CHAT_PRIVATE,
        to: to,
        msg_type: :MSG_STREAM,
        content: StreamContent.encode(sc),
        client_msg_id: "sm-#{System.unique_integer([:positive])}"
      },
      ctx
    )
  end
end
