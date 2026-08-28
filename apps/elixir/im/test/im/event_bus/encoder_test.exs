defmodule IM.EventBus.EncoderTest do
  use ExUnit.Case, async: true

  alias IM.EventBus.Encoder

  alias Pb.Im.Event.{
    AppEvent,
    DownstreamEvent,
    PushNotificationBatchEvent,
    SessionEvent,
    UpstreamEvent
  }

  test "upstream 默认 Protobuf" do
    bin =
      Encoder.encode(:upstream, %{
        msg_id: "m-pb-1",
        app_key: "a",
        from: "u1",
        device_id: "d1",
        trace_id: "t1",
        source: "websocket",
        ingress: "ws",
        cmd: 1,
        payload: <<1, 2>>,
        timestamp: 1_700_000_000_000
      })

    assert is_binary(bin)
    refute String.starts_with?(bin, "{")
    ev = UpstreamEvent.decode(bin)
    assert ev.app_key == "a"
    assert ev.user_id == "u1"
    assert ev.event_id == "m-pb-1"
    assert ev.trace_id == "t1"
    assert ev.payload == <<1, 2>>
  end

  test "session login/logout/heartbeat Protobuf" do
    for {type, expected} <- [
          {"login", :SESSION_LOGIN},
          {"logout", :SESSION_LOGOUT},
          {"heartbeat", :SESSION_HEARTBEAT},
          {:SESSION_LOGIN, :SESSION_LOGIN}
        ] do
      bin =
        Encoder.encode(:session, %{
          type: type,
          app_key: "a",
          user_id: "u",
          device_id: "d",
          platform: :ios,
          session_id: "s1",
          remote_ip: "127.0.0.1",
          reason: "test"
        })

      ev = SessionEvent.decode(bin)
      assert ev.event_type == expected
      assert ev.user_id == "u"
    end
  end

  test "downstream / push / app_events Protobuf（字符串键）" do
    down =
      Encoder.encode(:downstream, %{
        "msg_id" => "m-d",
        "app_key" => "a",
        "chat_type" => :CHAT_ROOM,
        "conv_id" => "c1",
        "cmd" => 2,
        "fanout" => %{
          "mode" => "room_aggregated",
          "recipient_count" => 3,
          "online_count" => 2,
          "audience" => %{
            "from_user_id" => "u1",
            "from_device_id" => "d1",
            "recipient_user_ids" => ["u2"],
            "recipient_list_truncated" => false,
            "recipient_list_max" => 50
          }
        },
        "payload" => <<>>
      })

    ev = DownstreamEvent.decode(down)
    assert ev.fanout.mode == :FANOUT_ROOM_AGGREGATED

    push =
      Encoder.encode(:push, %{
        "app_key" => "a",
        "msg_id" => "m-p",
        "conv_id" => "c1",
        "chat_type" => "CHAT_GROUP",
        "from_user_id" => "u1",
        "targets" => [%{"user_id" => "u2", "platform" => "ios", "push_token" => "tok"}]
      })

    pe = PushNotificationBatchEvent.decode(push)
    assert pe.chat_type == :CHAT_GROUP

    app =
      Encoder.encode(:app_events, %{
        "app_key" => "a",
        "channel_id" => "news:1",
        "direction" => :APP_EVENT_DOWN,
        "payload" => <<>>
      })

    ae = AppEvent.decode(app)
    assert ae.direction == :APP_EVENT_DOWN
  end

  test "upstream 内部/HTTP 来源与 session 未指定类型" do
    bin =
      Encoder.encode(:upstream, %{
        source: :EVENT_SOURCE_INTERNAL,
        ingress: :INGRESS_REST,
        route_key: "rk"
      })

    ev = UpstreamEvent.decode(bin)
    assert ev.source == :EVENT_SOURCE_INTERNAL
    assert ev.ingress == :INGRESS_REST

    sess = Encoder.encode(:session, %{type: "unknown"})
    assert SessionEvent.decode(sess).event_type == :SESSION_EVENT_UNSPECIFIED
  end

  test "downstream / push / app_events Protobuf" do
    down =
      Encoder.encode(:downstream, %{
        msg_id: "m-d",
        app_key: "a",
        chat_type: "CHAT_GROUP",
        conv_id: "c1",
        cmd: 2,
        fanout: %{
          mode: "group_aggregated",
          recipient_count: 3,
          online_count: 2,
          audience: %{
            from_user_id: "u1",
            from_device_id: "d1",
            recipient_user_ids: ["u2"],
            recipient_list_truncated: true,
            recipient_list_max: 100
          }
        },
        payload: <<>>
      })

    ev = DownstreamEvent.decode(down)
    assert ev.msg_id == "m-d"
    assert ev.fanout.mode == :FANOUT_GROUP_AGGREGATED

    push =
      Encoder.encode(:push, %{
        app_key: "a",
        msg_id: "m-p",
        conv_id: "c1",
        chat_type: :CHAT_PRIVATE,
        from_user_id: "u1",
        batch_index: 0,
        batch_total: 1,
        targets: [%{user_id: "u2", device_id: "d2", platform: :android, push_token: "tok"}]
      })

    pe = PushNotificationBatchEvent.decode(push)
    assert pe.msg_id == "m-p"
    assert hd(pe.targets).push_token == "tok"

    app =
      Encoder.encode(:app_events, %{
        app_key: "a",
        channel_id: "news:1",
        direction: "up",
        user_id: "u1",
        device_id: "d1",
        caller_service: "svc",
        content_type: "application/json",
        payload: "{}",
        client_event_id: "evt-1"
      })

    ae = AppEvent.decode(app)
    assert ae.channel_id == "news:1"
    assert ae.direction == :APP_EVENT_UP
  end

  test "未知 topic 走 json_envelope 兜底" do
    bin = Encoder.encode(:dlq, %{foo: %{bar: 1}, items: [1]})
    assert String.contains?(bin, "dlq")
    assert String.contains?(bin, "bar")
  end

  test "fanout direct 与未指定枚举" do
    down =
      Encoder.encode(:downstream, %{
        msg_id: "m-direct",
        fanout: %{mode: :direct, audience: %{}},
        chat_type: :CHAT_TYPE_UNSPECIFIED
      })

    ev = DownstreamEvent.decode(down)
    assert ev.fanout.mode == :FANOUT_DIRECT

    up =
      Encoder.encode(:upstream, %{
        source: "internal",
        ingress: "rest",
        cmd: "not-int"
      })

    assert UpstreamEvent.decode(up).source == :EVENT_SOURCE_INTERNAL
  end

  test "json_envelope 可选" do
    prev = Application.get_env(:im, :event_bus_kafka)

    Application.put_env(
      :im,
      :event_bus_kafka,
      Keyword.put(prev || [], :serialization, :json_envelope)
    )

    on_exit(fn ->
      if prev,
        do: Application.put_env(:im, :event_bus_kafka, prev),
        else: Application.delete_env(:im, :event_bus_kafka)
    end)

    bin = Encoder.encode(:upstream, %{msg_id: "j-1"})
    assert String.contains?(bin, "j-1")
  end
end
