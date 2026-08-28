defmodule IM.Jobs.UnreadFlush do
  @moduledoc """
  未读数 Redis → PG 异步刷库（设计 unread-count §11.1）。
  """

  alias IM.Stores.ConversationStore

  @doc "立即刷库（测试 / 运维）。"
  @spec run_once(keyword()) :: map()
  def run_once(opts \\ []) do
    app_key = Keyword.get(opts, :app_key, "app_demo")
    batch = Keyword.get(opts, :batch, 500)
    result = ConversationStore.flush_pending(app_key, batch: batch)

    :telemetry.execute([:im, :unread_flush], %{count: result.flushed}, result)
    result
  end

  @doc "入队 Oban 异步刷库。"
  @spec enqueue(keyword()) :: :ok
  def enqueue(opts \\ []) do
    args =
      %{}
      |> maybe_put("app_key", Keyword.get(opts, :app_key))
      |> maybe_put("batch", Keyword.get(opts, :batch))

    case args |> IM.Workers.UnreadFlush.new() |> Oban.insert() do
      {:ok, _} -> :ok
      {:error, _} ->
        _ = run_once(opts)
        :ok
    end
  end

  defp maybe_put(map, _k, nil), do: map
  defp maybe_put(map, k, v), do: Map.put(map, k, v)
end
