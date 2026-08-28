defmodule IM.LoadTest.Scenarios.UnreadBump do
  @moduledoc """
  未读热路径压测（LT-33）：并发发消息（Redis INCR）+ REST 会话列表读。

  偶数 `users`：前半向对端发消息，后半轮询 `GET /conversations`；
  可选 `read_every` 周期性已读清零。
  """

  alias IM.LoadTest.{Metrics, Reporter, UserBootstrap, Worker}

  @doc """
  运行 unread_bump。

  ## opts

  - `:users` — 虚拟用户数（自动调整为偶数，默认 10）
  - `:iterations` — 每发送方消息条数
  - `:polls` — 每接收方列表轮询次数
  - `:poll_interval_ms` — 轮询间隔（默认 50）
  - `:read_every` — 每 N 次轮询对已读会话 mark_read；0 表示不已读
  """
  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(opts \\ []) do
    users = Keyword.get(opts, :users, 10) |> ensure_even()
    iterations = Keyword.get(opts, :iterations, 30)
    polls = Keyword.get(opts, :polls, 20)
    poll_interval = Keyword.get(opts, :poll_interval_ms, 50)
    read_every = Keyword.get(opts, :read_every, 0)
    concurrency = Keyword.get(opts, :concurrency, users)
    timeout = Keyword.get(opts, :timeout_ms, 300_000)

    app_key = Keyword.fetch!(opts, :app_key)
    base_url = Keyword.get(opts, :base_url, "http://localhost:4000")
    password = Keyword.get(opts, :password, "password")
    prefix = Keyword.get(opts, :user_prefix, "lt_ub_")

    Metrics.reset()
    t0 = System.monotonic_time(:millisecond)

    {senders, receivers} = build_pairs(users, prefix, base_url, app_key, password, iterations)

    with :ok <- UserBootstrap.ensure_users(senders ++ receivers) do
      receiver_task =
        Task.async(fn ->
          Enum.reduce(1..polls, :ok, fn poll_i, :ok ->
            receivers
            |> Task.async_stream(
              fn cfg -> Worker.run_unread_poll(cfg, poll_i, read_every) end,
              max_concurrency: concurrency,
              timeout: timeout,
              on_timeout: :kill_task
            )
            |> Enum.reduce(:ok, fn
              {:ok, :ok}, :ok -> :ok
              _, :ok -> :ok
              _, err -> err
            end)

            if poll_i < polls, do: Process.sleep(poll_interval)
            :ok
          end)
        end)

      sender_results =
        senders
        |> Task.async_stream(
          &Worker.run_unread_sender/1,
          max_concurrency: concurrency,
          timeout: timeout,
          on_timeout: :kill_task,
          zip_input_on_exit: true
        )
        |> Enum.map(fn
          {:ok, res} -> res
          {:exit, reason} -> {:error, {:exit, reason}}
        end)

      :ok = Task.await(receiver_task, timeout)

      duration = System.monotonic_time(:millisecond) - t0
      report = Reporter.build("unread_bump", duration, Metrics.snapshot())
      report = Map.put(report, :worker_results, summarize(sender_results))
      Reporter.write!(report, Keyword.get(opts, :report_path))
      {:ok, report}
    else
      {:error, _} = err -> err
    end
  end

  defp ensure_even(n) when rem(n, 2) == 0, do: n
  defp ensure_even(n), do: n + 1

  defp build_pairs(users, prefix, base_url, app_key, password, iterations) do
    half = div(users, 2)

    base = %{
      base_url: base_url,
      app_key: app_key,
      password: password,
      iterations: iterations,
      platform: "loadtest",
      sdk_ver: "0.1.0"
    }

    senders =
      for i <- 1..half do
        uid = "#{prefix}s#{i}"
        peer = "#{prefix}r#{i}"

        base
        |> Map.merge(%{
          user_id: uid,
          device_id: "lt-ub-s-#{i}",
          peer_user_id: peer,
          role: :sender
        })
      end

    receivers =
      for i <- 1..half do
        uid = "#{prefix}r#{i}"
        peer = "#{prefix}s#{i}"

        base
        |> Map.merge(%{
          user_id: uid,
          device_id: "lt-ub-r-#{i}",
          peer_user_id: peer,
          role: :receiver
        })
      end

    {senders, receivers}
  end

  defp summarize(results) do
    ok = Enum.count(results, &(&1 == :ok))
    %{ok: ok, error: length(results) - ok, total: length(results)}
  end
end
