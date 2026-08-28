defmodule IM.MixProject do
  use Mix.Project

  def project do
    [
      app: :im,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      releases: releases(),
      test_coverage: [tool: ExCoveralls],
      # test/support 是 Case 模板，不是测试文件
      test_ignore_filters: [&String.starts_with?(&1, "test/support/")],
      name: "IM",
      docs: docs()
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.html": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :runtime_tools, :crypto],
      mod: {IM.Application, []}
    ]
  end

  # 测试环境额外编译 test/support（工厂、Case 模板）
  defp elixirc_paths(:test) do
    im_client_support = Path.expand("../im_client/test/support", __DIR__)
    ["lib", "test/support", im_client_support]
  end

  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:im_proto, path: "../im_proto"},
      # Web / WebSocket 接入
      {:phoenix, "~> 1.8"},
      {:bandit, "~> 1.7"},
      {:jason, "~> 1.4"},
      # 协议编解码：proto/ 下的 .proto 由 protoc-gen-elixir 生成到 lib/pb/。
      # 生成器插件版本必须与本依赖一致（mise 任务 proto-plugin 装同版本），
      # 否则生成物可能用到运行时库没有的 API。
      {:protobuf, "~> 0.17.0"},
      # 持久化
      {:ecto_sql, "~> 3.13"},
      {:phoenix_ecto, "~> 4.6"},
      {:postgrex, ">= 0.0.0"},
      # 后台任务（P5-11 / P7-09 / P7-10）
      {:oban, "~> 2.19"},
      # 缓存（P9-02）
      {:redix, "~> 1.5"},
      # Kafka 旁路 Producer（P9-03）
      {:brod, "~> 4.4"},
      # 集群（P9-01）
      {:libcluster, "~> 3.5"},
      # 可观测性
      {:telemetry_metrics, "~> 1.1"},
      {:telemetry_poller, "~> 1.3"},
      {:telemetry_metrics_prometheus_core, "~> 1.2"},
      # 开发与测试工具
      {:ex_doc, "~> 0.38", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: :test, runtime: false},
      # 协议 E2E：仅测试环境依赖 im_client（IC-06 不做 compile-time 硬依赖）
      {:im_client, path: "../im_client", only: :test}
    ]
  end

  # Release：`bin/im start` 启动；`bin/migrate` 见 rel/overlays/bin/migrate
  defp releases do
    [
      im: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent]
      ]
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "test.cluster": ["ecto.create --quiet", "ecto.migrate --quiet", "test --only cluster_e2e"],
      "test.trace": [
        "ecto.create --quiet",
        "ecto.migrate --quiet",
        "cmd env TRACE_EXPORT=1 CLUSTER_E2E=1 mix test test/im_client/protocol/ --exclude trace_coverage"
      ]
    ]
  end

  # 不把 docs/ 下的设计文档收进 extras：那些文档相互间是仓库内相对链接，
  # 搬进 ExDoc 后会全部失效并刷屏警告。协议规范请直接看 docs/design/protocol/protocol.md。
  defp docs do
    [main: "IM"]
  end
end
