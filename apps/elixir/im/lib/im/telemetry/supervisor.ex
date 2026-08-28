defmodule IM.Telemetry.Supervisor do
  @moduledoc """
  指标聚合与 VM poller 监督树（P9-05）。

  使用 `TelemetryMetricsPrometheus.Core`（无独立 HTTP 端口），
  由 Phoenix `GET /metrics` 调用 `scrape/0` 导出。
  """

  use Supervisor

  alias IM.Telemetry.Metrics

  @doc """
  启动 Telemetry 监督树。

  ## 示例

      {IM.Telemetry.Supervisor, []}
  """
  @spec start_link(term()) :: Supervisor.on_start()
  def start_link(arg \\ []) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000},
      {TelemetryMetricsPrometheus.Core,
       metrics: Metrics.metrics(), name: :im_prometheus_metrics, start_async: false}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Prometheus exposition 文本。

  ## 示例

      text = IM.Telemetry.Supervisor.scrape()
  """
  @spec scrape() :: String.t()
  def scrape do
    # last_value 在首次 poller tick 前为空；抓取前刷新，保证 /metrics 立即可用
    refresh_gauges()
    TelemetryMetricsPrometheus.Core.scrape(:im_prometheus_metrics)
  end

  defp periodic_measurements do
    [
      {__MODULE__, :refresh_gauges, []},
      :memory,
      :total_run_queue_lengths
    ]
  end

  @doc false
  def refresh_gauges do
    dispatch_connection_stats()

    :telemetry.execute([:vm, :memory], %{total: :erlang.memory(:total)}, %{})

    total =
      case :erlang.statistics(:total_run_queue_lengths) do
        %{total: t} -> t
        n when is_integer(n) -> n
        _ -> 0
      end

    :telemetry.execute([:vm, :total_run_queue_lengths], %{total: total}, %{})
    :ok
  end

  defp dispatch_connection_stats do
    active =
      try do
        Registry.count(IM.Connection.DeviceRegistry)
      rescue
        _ -> 0
      end

    :telemetry.execute(
      [:im, :connection, :stats],
      %{active: active},
      %{host: IM.Telemetry.Tags.host(), node: IM.Telemetry.Tags.node_name()}
    )
  end
end
