defmodule IM.LoadTest.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [{IM.LoadTest.Metrics, []}]
    Supervisor.start_link(children, strategy: :one_for_one, name: IM.LoadTest.Supervisor)
  end
end
