defmodule IM.Proto.MixProject do
  use Mix.Project

  @moduledoc false

  def project do
    [
      app: :im_proto,
      version: "0.1.0",
      elixir: "~> 1.19",
      deps: deps(),
      name: "IM.Proto"
    ]
  end

  defp deps do
    [
      {:protobuf, "~> 0.17.0"}
    ]
  end
end
