defmodule Mix.Tasks.Loadtest.Run do
  @shortdoc "运行 IM 压测场景"

  @moduledoc """
  ## 用法

      mix loadtest.run connection_load --app-key KEY --users 100
      mix loadtest.run message_flood --app-key KEY --users 20 --iterations 50
      mix loadtest.run unread_bump --app-key KEY --users 10 --iterations 30 --polls 20

  ## 选项

  - `--base-url` 默认 `http://localhost:4000`
  - `--ws-url` 可选
  - `--app-key` 必填
  - `--password` 默认 `password`
  - `--users` 虚拟用户数
  - `--concurrency` 最大并发
  - `--iterations` message_flood / unread_bump 每发送方消息数
  - `--polls` unread_bump 接收方列表轮询次数
  - `--read-every` unread_bump 每 N 次轮询 mark_read（0=否）
  - `--poll-interval-ms` unread_bump 轮询间隔
  - `--user-prefix` 默认 `lt_user_`
  - `--report` 报告 JSON 路径
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {scenario, rest} =
      case args do
        [name | rest] -> {name, rest}
        [] -> Mix.raise("用法: mix loadtest.run <scenario> [opts]")
      end

    {opts, _argv, _invalid} =
      OptionParser.parse(rest,
        strict: [
          base_url: :string,
          ws_url: :string,
          app_key: :string,
          password: :string,
          users: :integer,
          concurrency: :integer,
          iterations: :integer,
          user_prefix: :string,
          report: :string,
          timeout_ms: :integer,
          polls: :integer,
          read_every: :integer,
          poll_interval_ms: :integer
        ],
        aliases: [u: :users, c: :concurrency]
      )

    unless opts[:app_key] do
      Mix.raise("--app-key 必填")
    end

    keyword =
      [
        base_url: opts[:base_url] || "http://localhost:4000",
        ws_url: opts[:ws_url],
        app_key: opts[:app_key],
        password: opts[:password] || "password",
        users: opts[:users] || 10,
        concurrency: opts[:concurrency],
        iterations: opts[:iterations] || 10,
        report_path: opts[:report],
        timeout_ms: opts[:timeout_ms] || 300_000,
        polls: opts[:polls],
        read_every: opts[:read_every],
        poll_interval_ms: opts[:poll_interval_ms]
      ]
      |> then(fn kw ->
        if opts[:user_prefix], do: Keyword.put(kw, :user_prefix, opts[:user_prefix]), else: kw
      end)
      |> then(fn kw ->
        if opts[:concurrency], do: Keyword.put(kw, :concurrency, opts[:concurrency]), else: kw
      end)
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    {:ok, report} =
      case scenario do
        "connection_load" ->
          IM.LoadTest.Controller.run(Keyword.put(keyword, :scenario, :connection_load))

        "message_flood" ->
          IM.LoadTest.Controller.run(Keyword.put(keyword, :scenario, :message_flood))

        "channel_subscribe" ->
          IM.LoadTest.Scenarios.ChannelSubscribe.run(keyword)

        "group_fanout" ->
          IM.LoadTest.Scenarios.GroupFanout.run(keyword)

        "room_broadcast" ->
          IM.LoadTest.Scenarios.RoomBroadcast.run(keyword)

        "unread_bump" ->
          IM.LoadTest.Scenarios.UnreadBump.run(keyword)

        other ->
          Mix.raise(
            "未知场景: #{other}（支持 connection_load | message_flood | channel_subscribe | group_fanout | room_broadcast | unread_bump）"
          )
      end

    Mix.shell().info("压测完成 scenario=#{report.scenario} qps=#{report.qps}")
  end
end
