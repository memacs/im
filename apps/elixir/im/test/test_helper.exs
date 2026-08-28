exclude =
  []
  |> then(fn tags ->
    if System.get_env("CLUSTER_E2E") != "1", do: [{:cluster_e2e, true} | tags], else: tags
  end)
  |> then(fn tags ->
    if System.get_env("TRACE_EXPORT") == "1", do: [{:trace_coverage, true} | tags], else: tags
  end)

if exclude != [], do: ExUnit.configure(exclude: exclude)

if System.get_env("TRACE_EXPORT") == "1" do
  {:ok, _} = IM.ProtocolTraceRegistry.start_link()

  ExUnit.after_suite(fn _ ->
    {json, md} = IM.ProtocolTraceRegistry.dump!()
    IO.puts(:stderr, "[protocol trace] wrote #{json} and #{md}")
  end)
end

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(IM.Repo, :manual)
