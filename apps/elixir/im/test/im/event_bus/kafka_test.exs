defmodule IM.EventBus.KafkaTest do
  use IM.DataCase, async: false

  alias IM.EventBus
  alias IM.EventBus.Producer.Memory

  setup do
    prev_e = Application.get_env(:im, :event_bus_enabled)
    prev_i = Application.get_env(:im, :event_bus)
    prev_p = Application.get_env(:im, :event_bus_producer)

    Application.put_env(:im, :event_bus_enabled, true)
    Application.put_env(:im, :event_bus, IM.EventBus.Kafka)
    Application.put_env(:im, :event_bus_producer, Memory)
    Memory.reset!()

    on_exit(fn ->
      restore(:event_bus_enabled, prev_e)
      restore(:event_bus, prev_i)
      restore(:event_bus_producer, prev_p)
    end)

    :ok
  end

  test "Kafka 实现刷入 Memory Producer（Protobuf）" do
    assert :ok = EventBus.publish(:upstream, %{msg_id: "k-1", app_key: "a"})
    rows = Memory.snapshot()

    assert Enum.any?(rows, fn {topic, payload} ->
             topic == "im.upstream" and match_upstream?(payload, "k-1")
           end)
  end

  defp match_upstream?(payload, msg_id) do
    ev = Pb.Im.Event.UpstreamEvent.decode(payload)
    ev.event_id == msg_id or String.contains?(ev.event_id, msg_id)
  rescue
    _ -> false
  end

  defp restore(key, nil), do: Application.delete_env(:im, key)
  defp restore(key, val), do: Application.put_env(:im, key, val)
end
