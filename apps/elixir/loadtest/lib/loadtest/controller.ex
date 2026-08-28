defmodule IM.LoadTest.Controller do
  @moduledoc "场景编排：并发 Worker、超时汇总、报告输出。"

  alias IM.LoadTest.{Metrics, Reporter, Worker}

  @doc """
  运行场景。

  ## opts

  - `:scenario` — `:connection_load` | `:message_flood`
  - `:users` — 虚拟用户数
  - `:concurrency` — 最大并发（默认 = users）
  - `:base_url` / `:ws_url` / `:app_key` / `:password`
  - `:user_prefix` — 用户 id 前缀，默认 `"lt_user_"`
  - `:iterations` — message_flood 每用户发送数
  - `:peer_offset` — 对端用户偏移（user_i → user_{i+offset}）
  - `:report_path` — JSON 输出路径（可选）
  - `:timeout_ms` — 全局超时
  """
  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(opts) when is_list(opts) do
    scenario = Keyword.fetch!(opts, :scenario) |> to_string()
    users = Keyword.get(opts, :users, 10)
    concurrency = Keyword.get(opts, :concurrency, users)
    timeout = Keyword.get(opts, :timeout_ms, 300_000)

    Metrics.reset()
    t0 = System.monotonic_time(:millisecond)

    configs = build_configs(opts, users)

    results =
      configs
      |> Task.async_stream(
        fn cfg -> dispatch(scenario, cfg) end,
        max_concurrency: concurrency,
        timeout: timeout,
        on_timeout: :kill_task,
        zip_input_on_exit: true
      )
      |> Enum.map(fn
        {:ok, res} -> res
        {:exit, reason} -> {:error, {:exit, reason}}
      end)

    duration = System.monotonic_time(:millisecond) - t0
    report = Reporter.build(scenario, duration, Metrics.snapshot())
    report = Map.put(report, :worker_results, summarize_results(results))

    path = Keyword.get(opts, :report_path)
    Reporter.write!(report, path)
    {:ok, report}
  end

  defp dispatch("connection_load", cfg), do: Worker.run_connection(cfg)
  defp dispatch("message_flood", cfg), do: Worker.run_message_flood(cfg)
  defp dispatch(other, _), do: {:error, {:unknown_scenario, other}}

  defp build_configs(opts, users) do
    base = %{
      base_url: Keyword.get(opts, :base_url, "http://localhost:4000"),
      ws_url: Keyword.get(opts, :ws_url),
      app_key: Keyword.fetch!(opts, :app_key),
      password: Keyword.get(opts, :password, "password"),
      iterations: Keyword.get(opts, :iterations, 10),
      platform: "loadtest",
      sdk_ver: "0.1.0"
    }

    prefix = Keyword.get(opts, :user_prefix, "lt_user_")
    peer_offset = Keyword.get(opts, :peer_offset, 1)

    for i <- 1..users do
      uid = "#{prefix}#{i}"
      peer = "#{prefix}#{rem(i + peer_offset - 1, users) + 1}"

      Map.merge(base, %{
        user_id: uid,
        device_id: "lt-dev-#{i}",
        peer_user_id: peer
      })
    end
  end

  defp summarize_results(results) do
    ok = Enum.count(results, &(&1 == :ok))
    err = length(results) - ok
    %{ok: ok, error: err, total: length(results)}
  end
end
