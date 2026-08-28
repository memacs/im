defmodule IM.EventBus.Producer.Memory do
  @moduledoc "测试用 Producer：记录到 ETS，不连 Kafka。"

  @behaviour IM.EventBus.Producer

  @table :im_event_bus_produced

  def ensure_table! do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:named_table, :public, :bag, write_concurrency: true])

      _ ->
        :ok
    end

    :ok
  end

  def reset! do
    ensure_table!()
    true = :ets.delete_all_objects(@table)
    :ok
  end

  @doc "取出已产出记录 `{topic, payload}`。"
  def snapshot do
    ensure_table!()
    :ets.tab2list(@table)
  end

  @impl true
  def produce(topic, payload, _opts) do
    ensure_table!()
    true = :ets.insert(@table, {topic, payload})
    :telemetry.execute([:im, :event_bus, :produce], %{count: 1}, %{topic: topic})
    :ok
  end
end
