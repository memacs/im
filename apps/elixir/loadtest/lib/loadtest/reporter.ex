defmodule IM.LoadTest.Reporter do
  @moduledoc "将 Metrics 快照汇总为 JSON 报告。"

  @doc "根据场景名、耗时与 ETS 快照生成报告 map。"
  @spec build(String.t(), non_neg_integer(), list()) :: map()
  def build(scenario, duration_ms, rows) when is_binary(scenario) and is_list(rows) do
    ops =
      rows
      |> Enum.reduce(%{}, fn
        {{:ok, op}, n}, acc ->
          put_in_op(acc, op, :success, n)

        {{:err, op}, n}, acc ->
          put_in_op(acc, op, :failure, n)

        {{:sample, op, _}, ms}, acc ->
          Map.update(acc, op, %{samples: [ms]}, fn data ->
            Map.update(data, :samples, [ms], &[ms | &1])
          end)

        {{:err_reason, op, reason}, n}, acc ->
          Map.update(acc, op, %{errors: %{reason => n}}, fn data ->
            Map.update(data, :errors, %{reason => n}, &Map.update(&1, reason, n, fn v -> v + n end))
          end)

        _, acc ->
          acc
      end)
      |> Map.new(fn {op, data} ->
        samples = Enum.sort(data[:samples] || [])
        success = data[:success] || 0
        failure = data[:failure] || 0
        total = success + failure

        {op,
         %{
           success: success,
           failure: failure,
           total: total,
           success_rate: if(total == 0, do: 0.0, else: success / total),
           latency: percentiles(samples),
           errors: data[:errors] || %{}
         }}
      end)

    total_ok =
      ops
      |> Map.values()
      |> Enum.reduce(0, fn v, acc -> acc + v.success end)

    qps = if duration_ms <= 0, do: 0.0, else: total_ok * 1000.0 / duration_ms

    %{
      scenario: scenario,
      duration_ms: duration_ms,
      qps: Float.round(qps, 2),
      ops: ops,
      notes: notes(scenario)
    }
  end

  @doc "写出 JSON 文件或 stdout。"
  def write!(report, path \\ nil) do
    json = Jason.encode!(report, pretty: true)

    if path do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, json)
      path
    else
      IO.puts(json)
      :stdio
    end
  end

  defp put_in_op(acc, op, key, n) do
    Map.update(acc, op, %{key => n}, &Map.put(&1, key, n))
  end

  defp percentiles([]), do: %{avg_ms: 0, p50_ms: 0, p90_ms: 0, p99_ms: 0, max_ms: 0}

  defp percentiles(sorted) do
    n = length(sorted)
    avg = Enum.sum(sorted) / n

    %{
      avg_ms: Float.round(avg * 1.0, 2),
      p50_ms: percentile_at(sorted, 0.50),
      p90_ms: percentile_at(sorted, 0.90),
      p99_ms: percentile_at(sorted, 0.99),
      max_ms: List.last(sorted)
    }
  end

  defp percentile_at(sorted, p) do
    n = length(sorted)
    idx = max(0, min(n - 1, trunc(p * (n - 1))))
    Enum.at(sorted, idx)
  end

  defp notes("connection_load") do
    "目标：单节点 3–5 万连接（见 roadmap P10-01）。本报告为当次运行实测，瓶颈见 docs/implementation/elixir/loadtest-report.md。"
  end

  defp notes("message_flood") do
    "P10-02 单聊 QPS 基线；大群扇出见 LT-30 group_fanout。"
  end

  defp notes("unread_bump") do
    "LT-33：Redis 未读 bump + REST 会话列表；可选 mark_read。"
  end

  defp notes("channel_subscribe") do
    "P11-05 / LT-31：订阅建连基线；10 万订阅与丢包率需目标环境实测。"
  end

  defp notes(_), do: ""
end
