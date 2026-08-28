defmodule IM.ProtocolTraceRegistry do
  @moduledoc false

  @agent IM.ProtocolTraceRegistry

  @json_path Path.expand(
               "../../../../../docs/implementation/elixir/protocol-e2e-traces.json",
               __DIR__
             )
  @md_path Path.expand(
             "../../../../../docs/implementation/elixir/protocol-e2e-message-sequences.md",
             __DIR__
           )

  def enabled?, do: System.get_env("TRACE_EXPORT") == "1"

  def start_link do
    Agent.start_link(fn -> [] end, name: @agent)
  end

  def record(entry) when is_map(entry) do
    Agent.update(@agent, fn acc -> acc ++ [entry] end)
  end

  def all, do: Agent.get(@agent, & &1)

  def dump! do
    traces = all()
    File.write!(@json_path, Jason.encode!(traces, pretty: true))
    IM.ProtocolTraceRender.write!(@md_path, traces)
    {@json_path, @md_path}
  end

  def json_path, do: @json_path
  def md_path, do: @md_path
end
