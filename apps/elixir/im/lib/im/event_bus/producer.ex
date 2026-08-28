defmodule IM.EventBus.Producer do
  @moduledoc """
  Kafka 产出抽象。

  - 默认 `Memory`（ETS，测试/本地）
  - 生产：`IM.EventBus.Producer.Brod`（env：`EVENT_BUS_PRODUCER=brod` + `KAFKA_BROKERS`）
  """

  @callback produce(String.t(), binary(), keyword()) :: :ok | {:error, term()}

  @doc """
  产出一条记录到 Kafka topic 名。

  ## 示例

      :ok = IM.EventBus.Producer.produce("im.upstream", <<1>>, key: "m1")
  """
  @spec produce(String.t(), binary(), keyword()) :: :ok | {:error, term()}
  def produce(topic, payload, opts \\ [])
      when is_binary(topic) and is_binary(payload) do
    impl().produce(topic, payload, opts)
  end

  defp impl do
    Application.get_env(:im, :event_bus_producer, IM.EventBus.Producer.Memory)
  end
end
