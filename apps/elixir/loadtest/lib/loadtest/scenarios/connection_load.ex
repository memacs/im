defmodule IM.LoadTest.Scenarios.ConnectionLoad do
  @moduledoc "连接压测场景（P10-01 / LT-10）。"

  alias IM.LoadTest.Controller

  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(opts \\ []) do
    opts
    |> Keyword.put(:scenario, :connection_load)
    |> Controller.run()
  end
end
