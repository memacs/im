defmodule IM.LoadTest.Scenarios.ChannelSubscribe do
  @moduledoc """
  App Channel 订阅压测（P11-05 / LT-31）。

  建连 AUTH → `CMD_CHANNEL_SUBSCRIBE_REQ`；10 万订阅与丢包率需目标环境实测归档。
  """

  alias IM.Client
  alias IM.LoadTest.{Metrics, Reporter, UserBootstrap}

  @doc "运行订阅场景。"
  @spec run(keyword()) :: {:ok, map()}
  def run(opts \\ []) do
    users = Keyword.get(opts, :users, 10)
    channel_id = Keyword.get(opts, :channel_id, "fleet:alert")
    app_key = Keyword.fetch!(opts, :app_key)
    base_url = Keyword.get(opts, :base_url, "http://localhost:4000")
    password = Keyword.get(opts, :password, "password")
    prefix = Keyword.get(opts, :user_prefix, "lt_user_")
    concurrency = Keyword.get(opts, :concurrency, users)

    Metrics.reset()
    t0 = System.monotonic_time(:millisecond)

    1..users
    |> Task.async_stream(
      fn i ->
        run_one(%{
          base_url: base_url,
          app_key: app_key,
          password: password,
          user_id: "#{prefix}#{i}",
          device_id: "lt-ch-#{i}",
          channel_id: channel_id
        })
      end,
      max_concurrency: concurrency,
      timeout: Keyword.get(opts, :timeout_ms, 120_000),
      on_timeout: :kill_task
    )
    |> Enum.to_list()

    duration = System.monotonic_time(:millisecond) - t0
    report = Reporter.build("channel_subscribe", duration, Metrics.snapshot())
    Reporter.write!(report, Keyword.get(opts, :report_path))
    {:ok, report}
  end

  defp run_one(cfg) do
    t0 = System.monotonic_time(:millisecond)

    with {:ok, session} <- UserBootstrap.ensure_user(cfg),
         ws_url <- List.first(session.websocket_urls) || default_ws(cfg.base_url),
         {:ok, client} <- Client.start_link(url: ws_url),
         :ok <- Client.connect(client),
         {:ok, _} <-
           Client.authenticate(client, %{
             app_key: cfg.app_key,
             user_id: cfg.user_id,
             token: session.access_token,
             device_id: cfg.device_id
           }),
         {:ok, _packet} <- Client.subscribe_channels(client, [cfg.channel_id]) do
      Metrics.success(:channel_subscribe, System.monotonic_time(:millisecond) - t0)
      Client.disconnect(client)
      :ok
    else
      {:error, reason} ->
        Metrics.failure(:channel_subscribe, reason)
        {:error, reason}
    end
  end

  defp default_ws(base_url) do
    base_url
    |> String.replace_prefix("https://", "wss://")
    |> String.replace_prefix("http://", "ws://")
    |> String.trim_trailing("/")
    |> Kernel.<>("/ws")
  end
end
