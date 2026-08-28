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
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.html": :test
      ],
      name: "IM",
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :runtime_tools],
      mod: {IM.Application, []}
    ]
  end

  # 测试环境额外编译 test/support（工厂、Case 模板）
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Web / WebSocket 接入
      {:phoenix, "~> 1.8"},
      {:bandit, "~> 1.7"},
      {:jason, "~> 1.4"},
      # 持久化
      {:ecto_sql, "~> 3.13"},
      {:phoenix_ecto, "~> 4.6"},
      {:postgrex, ">= 0.0.0"},
      # 可观测性
      {:telemetry_metrics, "~> 1.1"},
      {:telemetry_poller, "~> 1.3"},
      # 开发与测试工具
      {:ex_doc, "~> 0.38", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: :test, runtime: false}
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
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end

  # 不把 docs/ 下的设计文档收进 extras：那些文档相互间是仓库内相对链接，
  # 搬进 ExDoc 后会全部失效并刷屏警告。协议规范请直接看 docs/design/protocol/protocol.md。
  defp docs do
    [main: "IM"]
  end
end
