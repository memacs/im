defmodule IM.LoadTest.Scenarios.MessageFlood do
  @moduledoc "单聊消息 QPS 基线（P10-02 / LT-11）。"

  alias IM.LoadTest.Controller

  @spec run(keyword()) :: {:ok, map()} | {:error, term()}
  def run(opts \\ []) do
    opts
    |> Keyword.put(:scenario, :message_flood)
    |> Controller.run()
  end
end
