defmodule IM.Jobs.TtlPurge do
  @moduledoc """
  消息 TTL 清理（P7-10 / DD-040）。执行体供 Oban Worker / 测试同步调用。
  """

  alias IM.Stores.{MessageStore, PassthroughStore}

  @doc """
  立即执行一轮清理（测试与运维用）。
  """
  @spec run_once(keyword()) :: map()
  def run_once(opts \\ []), do: purge(opts)

  @doc """
  入队 Oban 异步清理。
  """
  @spec enqueue(keyword()) :: :ok
  def enqueue(opts \\ []) do
    args =
      %{}
      |> maybe_put_arg("app_key", Keyword.get(opts, :app_key))
      |> maybe_put_arg("msg_ttl_days", Keyword.get(opts, :msg_ttl_days))
      |> maybe_put_arg("batch", Keyword.get(opts, :batch))

    case args |> IM.Workers.TtlPurge.new() |> Oban.insert() do
      {:ok, _} -> :ok
      {:error, _} ->
        _ = purge(opts)
        :ok
    end
  end

  @doc false
  def purge(opts) do
    app_key = Keyword.get(opts, :app_key, "app_demo")
    days = Keyword.get(opts, :msg_ttl_days, Application.get_env(:im, :msg_ttl_days, 7))
    batch = Keyword.get(opts, :batch, 500)

    cutoff =
      DateTime.utc_now() |> DateTime.add(-days * 86_400, :second) |> DateTime.truncate(:microsecond)

    msg_ids = MessageStore.list_expired_msg_ids(app_key, cutoff, batch)
    deleted = if msg_ids == [], do: %{inbox: 0, bodies: 0}, else: MessageStore.delete_messages(app_key, msg_ids)

    room_cutoff =
      DateTime.utc_now() |> DateTime.add(-300, :second) |> DateTime.truncate(:microsecond)

    room_n = MessageStore.delete_expired_room_bodies(room_cutoff, batch)
    pt_n = PassthroughStore.delete_expired(batch)

    result = %{chat: deleted, room: room_n, passthrough: pt_n}

    :telemetry.execute([:im, :ttl_purge], %{count: length(msg_ids) + room_n + pt_n}, result)
    result
  end

  defp maybe_put_arg(map, _k, nil), do: map
  defp maybe_put_arg(map, k, v), do: Map.put(map, k, v)
end
