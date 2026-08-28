defmodule IM.Workers.MessageBurn do
  @moduledoc "阅后即焚 Oban Worker（P7-09）。"

  use Oban.Worker, queue: :message_burn, max_attempts: 5

  alias IM.Jobs.MessageBurn

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    app_key = Map.fetch!(args, "app_key")
    msg_id = Map.fetch!(args, "msg_id")
    due_at_ms = Map.get(args, "due_at_ms")
    meta = args |> Map.get("meta", %{}) |> to_keyword()
    MessageBurn.execute(app_key, msg_id, meta, due_at_ms)
    :ok
  end

  defp to_keyword(map) when is_map(map) do
    []
    |> maybe(:from, Map.get(map, "from") || Map.get(map, :from))
    |> maybe(:to, Map.get(map, "to") || Map.get(map, :to))
    |> maybe(:conv_id, Map.get(map, "conv_id") || Map.get(map, :conv_id))
  end

  defp maybe(kw, _k, nil), do: kw
  defp maybe(kw, k, v), do: Keyword.put(kw, k, v)
end
