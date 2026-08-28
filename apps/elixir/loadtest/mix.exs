defmodule IM.LoadTest.MixProject do
  use Mix.Project

  def project do
    [
      app: :loadtest,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [
        loadtest: [
          include_executables_for: [:unix],
          applications: [runtime_tools: :permanent],
          overlays: "rel/overlays"
        ]
      ],
      name: "IM.LoadTest"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {IM.LoadTest.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:im_client, path: "../im_client"},
      {:jason, "~> 1.4"}
    ]
  end
end
