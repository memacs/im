defmodule IM.EventBus.Producer.BrodTest do
  use ExUnit.Case, async: false

  alias IM.EventBus.Producer.Brod

  defmodule FakeBrod do
    def produce_sync(client, topic, partition, key, value) do
      send(Process.get(:brod_test_pid), {:produce_sync, client, topic, partition, key, value})
      :ok
    end

    def start_client(_endpoints, _client_id, _config), do: :ok
    def stop_client(_client_id), do: :ok
  end

  defmodule FakeBrodFail do
    def produce_sync(_c, _t, _p, _k, _v), do: {:error, :broker_down}
  end

  setup do
    prev_adapter = Application.get_env(:im, :brod_adapter)
    prev_kafka = Application.get_env(:im, :event_bus_kafka)
    prev_producer = Application.get_env(:im, :event_bus_producer)

    Process.put(:brod_test_pid, self())
    Application.put_env(:im, :brod_adapter, FakeBrod)

    Application.put_env(
      :im,
      :event_bus_kafka,
      Keyword.merge(prev_kafka || [], brokers: [{"localhost", 9092}], client_id: :im_kafka_test)
    )

    on_exit(fn ->
      restore(:brod_adapter, prev_adapter)
      restore(:event_bus_kafka, prev_kafka)
      restore(:event_bus_producer, prev_producer)
    end)

    :ok
  end

  test "parse_brokers" do
    assert Brod.parse_brokers(nil) == []
    assert Brod.parse_brokers("kafka:9092") == [{"kafka", 9092}]
    assert Brod.parse_brokers("a:1,b:2") == [{"a", 1}, {"b", 2}]
    assert Brod.parse_brokers("bad") == []
  end

  test "produce 经 adapter 写出" do
    assert :ok = Brod.produce("im.upstream", "payload", key: "m-1")

    assert_receive {:produce_sync, :im_kafka_test, "im.upstream", :hash, "m-1", "payload"}
  end

  test "无 brokers 返回 not_configured" do
    Application.put_env(:im, :event_bus_kafka, brokers: [], client_id: :im_kafka_test)
    assert {:error, :kafka_not_configured} = Brod.produce("im.upstream", "x")
  end

  test "adapter 失败向上返回" do
    Application.put_env(:im, :brod_adapter, FakeBrodFail)
    assert {:error, :broker_down} = Brod.produce("im.upstream", "x", key: "k")
  end

  test "Client 经 adapter start_client" do
    assert {:ok, pid} = start_supervised(IM.EventBus.Producer.Brod.Client)
    assert Process.alive?(pid)
  end

  defp restore(key, nil), do: Application.delete_env(:im, key)
  defp restore(key, val), do: Application.put_env(:im, key, val)
end
