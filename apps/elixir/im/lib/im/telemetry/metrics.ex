defmodule IM.Telemetry.Metrics do
  @moduledoc """
  Prometheus 指标定义（P9-05 / DD-028 §2.3）。

  标签仅用低基数维度（`host` / `msg_type` / `direction` / `node` / `cmd`…），
  **禁止** `app_key` / `user_id` / `msg_id` / `trace_id`。
  """

  import Telemetry.Metrics

  @byte_buckets [256, 512, 1024, 2048, 4096, 8192, 16_384, 32_768, 65_536]
  @duration_buckets [5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000]

  @doc """
  返回 Telemetry.Metrics 定义列表。

  ## 示例

      metrics = IM.Telemetry.Metrics.metrics()
  """
  @spec metrics() :: [Telemetry.Metrics.t()]
  def metrics do
    packet_tags = [:cmd, :host, :msg_type, :direction, :node]

    [
      counter("im.packet.received.total",
        event_name: [:im, :packet, :received],
        measurement: :count,
        tags: packet_tags,
        tag_values: &stringify_tags/1
      ),
      sum("im.packet.received.bytes",
        event_name: [:im, :packet, :received],
        measurement: :bytes,
        unit: :byte,
        tags: packet_tags,
        tag_values: &stringify_tags/1
      ),
      distribution("im.packet.received.bytes_bucket",
        event_name: [:im, :packet, :received],
        measurement: :bytes,
        unit: :byte,
        tags: packet_tags,
        tag_values: &stringify_tags/1,
        reporter_options: [buckets: @byte_buckets]
      ),
      counter("im.packet.sent.total",
        event_name: [:im, :packet, :sent],
        measurement: :count,
        tags: packet_tags,
        tag_values: &stringify_tags/1
      ),
      sum("im.packet.sent.bytes",
        event_name: [:im, :packet, :sent],
        measurement: :bytes,
        unit: :byte,
        tags: packet_tags,
        tag_values: &stringify_tags/1
      ),
      distribution("im.packet.sent.bytes_bucket",
        event_name: [:im, :packet, :sent],
        measurement: :bytes,
        unit: :byte,
        tags: packet_tags,
        tag_values: &stringify_tags/1,
        reporter_options: [buckets: @byte_buckets]
      ),
      counter("im.packet.errors.total",
        event_name: [:im, :packet, :error],
        measurement: :count,
        tags: [:code, :ref_cmd, :host],
        tag_values: &stringify_tags/1
      ),
      distribution("im.handler.duration.ms",
        event_name: [:im, :handler, :stop],
        measurement: :duration,
        unit: {:native, :millisecond},
        tags: [:cmd, :result, :host, :msg_type, :direction],
        tag_values: &stringify_tags/1,
        reporter_options: [buckets: @duration_buckets]
      ),
      distribution("im.ack.latency.ms",
        event_name: [:im, :ack, :latency],
        measurement: :duration,
        unit: {:native, :millisecond},
        tags: [:stage, :chat_type, :host, :msg_type],
        tag_values: &stringify_tags/1,
        reporter_options: [buckets: @duration_buckets]
      ),
      last_value("im.connections.active",
        event_name: [:im, :connection, :stats],
        measurement: :active,
        tags: [:host, :node],
        tag_values: &stringify_tags/1
      ),
      counter("im.connections.total",
        event_name: [:im, :connection, :opened],
        measurement: :count,
        tags: [:host, :node],
        tag_values: &stringify_tags/1
      ),
      counter("im.auth.total",
        event_name: [:im, :auth, :result],
        measurement: :count,
        tags: [:result, :host],
        tag_values: &stringify_tags/1
      ),
      counter("im.outbound.dropped.total",
        event_name: [:im, :outbound, :dropped],
        measurement: :count,
        tags: [:priority, :host],
        tag_values: &stringify_tags/1
      ),
      last_value("im.outbound.queue.depth",
        event_name: [:im, :outbound, :depth],
        measurement: :depth,
        tags: [:priority, :host],
        tag_values: &stringify_tags/1
      ),
      distribution("im.outbound.wait.ms",
        event_name: [:im, :outbound, :wait],
        measurement: :duration,
        unit: {:native, :millisecond},
        tags: [:priority, :host],
        tag_values: &stringify_tags/1,
        reporter_options: [buckets: @duration_buckets]
      ),
      counter("im.outbound.aged.total",
        event_name: [:im, :outbound, :aged],
        measurement: :count,
        tags: [:from, :to, :host],
        tag_values: &stringify_tags/1
      ),
      distribution("im.storage.duration.ms",
        event_name: [:im, :storage, :stop],
        measurement: :duration,
        unit: {:native, :millisecond},
        tags: [:operation, :store, :host],
        tag_values: &stringify_tags/1,
        reporter_options: [buckets: @duration_buckets]
      ),
      distribution("im.delivery.duration.ms",
        event_name: [:im, :delivery, :stop],
        measurement: :duration,
        unit: {:native, :millisecond},
        tags: [:chat_type, :fanout_mode, :host, :msg_type],
        tag_values: &stringify_tags/1,
        reporter_options: [buckets: @duration_buckets]
      ),
      distribution("im.push.recipients",
        event_name: [:im, :delivery, :stop],
        measurement: :recipients,
        tags: [:chat_type, :fanout_mode, :host],
        tag_values: &stringify_tags/1,
        reporter_options: [buckets: [1, 2, 5, 10, 25, 50, 100, 250, 500, 1000]]
      ),
      counter("im.cross_node.dispatch.total",
        event_name: [:im, :cluster, :dispatch],
        measurement: :count,
        tags: [:host, :node],
        tag_values: &stringify_tags/1
      ),
      last_value("vm.memory.total",
        event_name: [:vm, :memory],
        measurement: :total,
        unit: {:byte, :byte}
      ),
      last_value("vm.total_run_queue_lengths.total",
        event_name: [:vm, :total_run_queue_lengths],
        measurement: :total
      ),
      counter("im.mobile_push.enqueue.count",
        event_name: [:im, :mobile_push, :enqueue],
        measurement: :count,
        tags: [:platform],
        tag_values: &stringify_tags/1
      ),
      counter("im.permission.check.count",
        event_name: [:im, :permission, :check],
        measurement: :count,
        tags: [:type, :result, :layer],
        tag_values: &stringify_tags/1
      ),
      counter("im.permission.cache_drift.count",
        event_name: [:im, :permission, :cache_drift],
        measurement: :count,
        tags: [:type],
        tag_values: &stringify_tags/1
      ),
      counter("im.event_bus.enqueue.count",
        event_name: [:im, :event_bus, :enqueue],
        measurement: :count,
        tags: [:topic],
        tag_values: &stringify_tags/1
      ),
      counter("im.event_bus.drop.count",
        event_name: [:im, :event_bus, :drop],
        measurement: :count,
        tags: [:topic],
        tag_values: &stringify_tags/1
      ),
      counter("im.event_bus.produce.count",
        event_name: [:im, :event_bus, :produce],
        measurement: :count,
        tags: [:topic],
        tag_values: &stringify_tags/1
      ),
      counter("im.event_bus.error.count",
        event_name: [:im, :event_bus, :error],
        measurement: :count,
        tags: [:topic],
        tag_values: &stringify_tags/1
      ),
      # 禁止 app_key/channel_id 作标签（高基数）；仅计总数
      counter("im.channel.aggregate_drop.count",
        event_name: [:im, :channel, :aggregate_drop],
        measurement: :count
      ),
      counter("im.msg_burn.scheduled.total",
        event_name: [:im, :msg_burn, :scheduled],
        measurement: :count,
        tags: [:host],
        tag_values: &stringify_tags/1
      ),
      counter("im.msg_burn.executed.total",
        event_name: [:im, :msg_burn, :executed],
        measurement: :count,
        tags: [:host],
        tag_values: &stringify_tags/1
      ),
      distribution("im.msg_burn.lag.ms",
        event_name: [:im, :msg_burn, :executed],
        measurement: :lag,
        unit: {:native, :millisecond},
        tags: [:host],
        tag_values: &stringify_tags/1,
        reporter_options: [buckets: @duration_buckets]
      )
    ]
  end

  defp stringify_tags(meta) when is_map(meta) do
    meta
    |> Map.take([
      :direction,
      :msg_type,
      :host,
      :node,
      :platform,
      :cmd,
      :result,
      :type,
      :layer,
      :code,
      :ref_cmd,
      :stage,
      :chat_type,
      :fanout_mode,
      :priority,
      :topic,
      :operation,
      :store,
      :from,
      :to
    ])
    |> Map.new(fn
      {k, v} when is_atom(v) -> {k, Atom.to_string(v)}
      {k, v} when is_integer(v) -> {k, Integer.to_string(v)}
      {k, v} when is_binary(v) -> {k, v}
      {k, v} -> {k, inspect(v)}
    end)
  end
end
