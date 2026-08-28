defmodule IM.EventBus do
  @moduledoc """
  Kafka 旁路 Facade（P9-03）。

  **不阻塞** SEND 主路径：默认入内存 Buffer；实现失败吞掉并记指标。
  """

  @callback publish(atom(), map(), keyword()) :: :ok

  @doc """
  发布旁路事件。

  ## 示例

      :ok = IM.EventBus.publish(:upstream, %{msg_id: "1"}, [])
  """
  @spec publish(atom(), map(), keyword()) :: :ok
  def publish(topic, event, opts \\ []) when is_atom(topic) and is_map(event) do
    write? = Keyword.get(opts, :write_kafka, true)

    if enabled?() and write? do
      try do
        impl().publish(topic, event, opts)
      rescue
        e ->
          :telemetry.execute([:im, :event_bus, :error], %{count: 1}, %{
            topic: topic,
            reason: Exception.message(e)
          })

          :ok
      catch
        kind, reason ->
          :telemetry.execute([:im, :event_bus, :error], %{count: 1}, %{
            topic: topic,
            reason: "#{kind}:#{inspect(reason)}"
          })

          :ok
      end
    else
      :ok
    end
  end

  @doc "是否启用旁路（默认关，避免无 Kafka 时堆积）。"
  @spec enabled?() :: boolean()
  def enabled? do
    Application.get_env(:im, :event_bus_enabled, false) == true
  end

  defp impl do
    Application.get_env(:im, :event_bus, IM.EventBus.Noop)
  end
end
