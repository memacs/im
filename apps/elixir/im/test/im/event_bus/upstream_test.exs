defmodule IM.EventBus.UpstreamTest do
  use ExUnit.Case, async: true

  alias IM.EventBus.Upstream
  alias IM.EventBus.Encoder
  alias Pb.Im.Event.UpstreamEvent
  alias Pb.Im.Protocol.{ChatMessage, MsgSendReq}

  test "encode_payload 为 MsgSendReq 字节" do
    msg = %ChatMessage{chat_type: :CHAT_PRIVATE, to: "b", msg_type: :MSG_TEXT, content: "hi"}
    bin = Upstream.encode_payload(msg)
    assert %MsgSendReq{message: ^msg} = MsgSendReq.decode(bin)
  end

  test "upstream Protobuf 含完整 payload 与 cmd" do
    msg = %ChatMessage{
      chat_type: :CHAT_PRIVATE,
      to: "b",
      msg_type: :MSG_TEXT,
      content: "kafka-body",
      client_msg_id: "c1"
    }

    payload = Upstream.encode_payload(msg)

    bin =
      Encoder.encode(:upstream, %{
        event_id: "m1",
        msg_id: "m1",
        app_key: "app",
        trace_id: "t1",
        source: :EVENT_SOURCE_HTTP,
        ingress: :INGRESS_REST,
        cmd: 100,
        user_id: "a",
        device_id: "d1",
        route_key: "conv",
        payload: payload
      })

    ev = UpstreamEvent.decode(bin)
    assert ev.cmd == 100
    assert ev.payload != <<>>
    assert %MsgSendReq{message: decoded} = MsgSendReq.decode(ev.payload)
    assert decoded.content == "kafka-body"
  end
end
