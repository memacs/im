defmodule IM.EventBus.Kafka do
  @moduledoc """
  Kafka 旁路实现：先入 Buffer，再 drain 到 `IM.EventBus.Producer`。

  无真实 broker 时用 `Producer.Memory`；配置 brod 后可替换 Producer。
  """

  @behaviour IM.EventBus

  alias IM.EventBus.{Buffer, Encoder, Producer}

  @topic_names %{
    upstream: "im.upstream",
    session: "im.session",
    downstream: "im.downstream",
    push: "im.push",
    app_events: "im.app_events",
    dlq: "im.dlq"
  }

  @impl true
  def publish(topic, event, _opts) do
    _ = Buffer.enqueue_and_flush(topic, event, batch_size())
    :ok
  end

  @doc "逻辑 atom topic → Kafka topic 名。"
  def topic_name(topic) when is_atom(topic) do
    conf = Application.get_env(:im, :event_bus_kafka, [])
    topics = Keyword.get(conf, :topics, %{})
    Map.get(topics, topic) || Map.get(@topic_names, topic) || "im.#{topic}"
  end

  @doc false
  def encode_and_produce(topic, event) do
    name = topic_name(topic)
    payload = Encoder.encode(topic, event)
    key = partition_key(event)

    case Producer.produce(name, payload, key: key) do
      :ok ->
        :ok

      {:error, reason} ->
        :telemetry.execute([:im, :event_bus, :produce_error], %{count: 1}, %{
          topic: name,
          reason: inspect(reason)
        })

        :ok
    end
  end

  defp partition_key(event) when is_map(event) do
    cond do
      is_binary(event[:msg_id]) and event[:msg_id] != "" -> event[:msg_id]
      is_binary(event["msg_id"]) and event["msg_id"] != "" -> event["msg_id"]
      is_binary(event[:event_id]) and event[:event_id] != "" -> event[:event_id]
      is_binary(event["event_id"]) and event["event_id"] != "" -> event["event_id"]
      is_binary(event[:trace_id]) and event[:trace_id] != "" -> event[:trace_id]
      is_binary(event["trace_id"]) and event["trace_id"] != "" -> event["trace_id"]
      true -> ""
    end
  end

  defp batch_size do
    conf = Application.get_env(:im, :event_bus_kafka, [])
    Keyword.get(conf, :batch_size, 100)
  end
end
