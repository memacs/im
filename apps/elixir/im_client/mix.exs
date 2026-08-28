defmodule IM.Client.MixProject do
  use Mix.Project

  def project do
    [
      app: :im_client,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      test_ignore_filters: [&String.starts_with?(&1, "test/support/")],
      name: "IM.Client"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:im_proto, path: "../im_proto"},
      {:websockex, "~> 0.4.3"},
      {:req, "~> 0.5"}
    ]
  end
end
