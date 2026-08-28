defmodule IM.EventBus.EncoderTest do
  use ExUnit.Case, async: true

  alias IM.EventBus.Encoder
  alias Pb.Im.Event.{SessionEvent, UpstreamEvent}

  test "upstream 默认 Protobuf" do
    bin =
      Encoder.encode(:upstream, %{
        msg_id: "m-pb-1",
        app_key: "a",
        from: "u1",
        device_id: "d1"
      })

    assert is_binary(bin)
    refute String.starts_with?(bin, "{")
    ev = UpstreamEvent.decode(bin)
    assert ev.app_key == "a"
    assert ev.user_id == "u1"
    assert ev.event_id == "m-pb-1"
  end

  test "session login Protobuf" do
    bin = Encoder.encode(:session, %{type: "login", app_key: "a", user_id: "u", device_id: "d"})
    ev = SessionEvent.decode(bin)
    assert ev.event_type == :SESSION_LOGIN
    assert ev.user_id == "u"
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
