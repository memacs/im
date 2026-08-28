defmodule IM.Client.Protocol.StreamTest do
  @moduledoc "流式：MSG_STREAM 分块推送 + 透传 stream_* action。"
  use IM.ClientProtocolCase

  alias IM.Client.{Assertions, Connection}
  alias IM.Services.StreamManager
  alias Pb.Im.Protocol.{ChatMessage, OfflinePullReq, Passthrough, StreamContent}

  setup do
    StreamManager.reset()
    :ok
  end

  @tag trace_case: "stream_test/MSG_STREAM 四段推送至对端"
  test "MSG_STREAM 四段推送至对端" do
    %{a: a, b: b} = connect_pair!()
    stream_id = unique_id("st")

    chunks = [
      {:STREAM_STATUS_START, 1, ""},
      {:STREAM_STATUS_ONGOING, 2, "Hel"},
      {:STREAM_STATUS_ONGOING, 3, "lo"},
      {:STREAM_STATUS_END, 4, ""}
    ]

    for {status, seq, chunk} <- chunks do
      trace_as!("A")

      send_stream_chunk!(
        a.client,
        a.login.user_id,
        b.login.user_id,
        stream_id,
        status,
        seq,
        chunk
      )

      trace_as!("B")
      push_packet = Assertions.assert_push(b.client) |> elem(1)
      trace!("↓ WS CMD_MSG_PUSH (#{status})", push_packet)
      push = decode_payload!(push_packet, ChatMessage)
      assert push.msg_type == :MSG_STREAM
      decoded = StreamContent.decode(push.content)
      assert decoded.stream_id == stream_id
      assert decoded.sequence == seq
    end

    assert {:ok, "Hello"} = StreamManager.assembled_text(a.login.app_key, stream_id)
  end

  @tag trace_case: "stream_test/流式透传 stream_start/chunk/end"
  test "流式透传 stream_start / stream_chunk / stream_end" do
    %{a: a, b: b} = connect_pair!()
    stream_id = unique_id("ps")

    steps = [
      {"stream_start", Jason.encode!(%{stream_id: stream_id})},
      {"stream_chunk", Jason.encode!(%{stream_id: stream_id, chunk: "Hi"})},
      {"stream_end", Jason.encode!(%{stream_id: stream_id})}
    ]

    for {action, data} <- steps do
      trace_as!("A")

      trace!("↑ WS CMD_PASSTHROUGH (#{action})", %Passthrough{
        chat_type: :CHAT_PRIVATE,
        from: a.login.user_id,
        to: b.login.user_id,
        action: action,
        data: data,
        persist: false
      })

      :ok =
        Connection.passthrough(a.client, %{
          chat_type: :CHAT_PRIVATE,
          from: a.login.user_id,
          to: b.login.user_id,
          action: action,
          data: data,
          persist: false
        })

      {:ok, packet} = Assertions.await_cmd(b.client, CmdType.value(:CMD_PASSTHROUGH), 5_000)
      trace_as!("B")
      trace!("↓ WS CMD_PASSTHROUGH (#{action})", packet)
      pt = decode_payload!(packet, Passthrough)
      assert pt.action == action
      assert pt.data == data
    end
  end

  @tag trace_case: "stream_test/MSG_STREAM 离线拉取"
  test "MSG_STREAM 离线拉取" do
    a = connect_authenticated!()
    login_b = AuthFixtures.login!(app_key: a.login.app_key)
    stream_id = unique_id("st-off")

    trace_as!("A")

    send_stream_chunk!(
      a.client,
      a.login.user_id,
      login_b.user_id,
      stream_id,
      :STREAM_STATUS_START,
      1,
      ""
    )

    send_stream_chunk!(
      a.client,
      a.login.user_id,
      login_b.user_id,
      stream_id,
      :STREAM_STATUS_ONGOING,
      2,
      "off"
    )

    send_stream_chunk!(
      a.client,
      a.login.user_id,
      login_b.user_id,
      stream_id,
      :STREAM_STATUS_END,
      3,
      ""
    )

    conv_id = IM.Domain.ConvId.private(a.login.user_id, login_b.user_id)
    b = connect_authenticated!(app_key: a.login.app_key, user_id: login_b.user_id)

    trace_as!("B")
    trace!("↑ WS CMD_OFFLINE_PULL_REQ", %OfflinePullReq{conv_id: conv_id, cursor: 0, limit: 20})

    {:ok, packet} = Connection.offline_pull(b.client, %{conv_id: conv_id, cursor: 0, limit: 20})
    trace!("↓ WS CMD_OFFLINE_PULL_RESP", packet)
    resp = assert_cmd_resp!(packet, :CMD_OFFLINE_PULL_RESP, Pb.Im.Protocol.OfflinePullResp)

    streams = Enum.filter(resp.messages, &(&1.msg_type == :MSG_STREAM))
    assert length(streams) == 3

    decoded = Enum.map(streams, fn %ChatMessage{content: bin} -> StreamContent.decode(bin) end)
    assert Enum.any?(decoded, &(&1.chunk == "off" and &1.status == :STREAM_STATUS_ONGOING))
    assert Enum.any?(decoded, &(&1.status == :STREAM_STATUS_END))
  end
end
