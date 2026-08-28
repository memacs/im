defmodule IM.Permission.BlockCache do
  @moduledoc """
  好友拉黑热缓存（DD-033）。权威源 PostgreSQL；热路径 L1 → L2 SET。

  键：`im:block:{app_key}:{blocker_user_id}`，成员为被拉黑 user_id。
  """

  alias IM.Cache
  alias IM.Permission.{Invalidator, L1, Telemetry}
  alias IM.Stores.FriendStore

  @doc "接收方 `blocker` 是否拉黑了 `blocked`（发送方）。"
  @spec blocked?(String.t(), String.t(), String.t()) :: boolean()
  def blocked?(app_key, blocker, blocked)
      when is_binary(app_key) and is_binary(blocker) and is_binary(blocked) do
    l1 = L1.block_key(app_key, blocker, blocked)

    case L1.get(l1) do
      {:ok, hit?} ->
        emit(:block, hit?, :l1)
        hit?

      :miss ->
        {hit?, layer} = blocked_l2(app_key, blocker, blocked)
        :ok = L1.put(l1, hit?)
        emit(:block, hit?, layer)
        hit?
    end
  end

  @doc "写穿：标记拉黑。"
  @spec put(String.t(), String.t(), String.t()) :: :ok
  def put(app_key, blocker, blocked) do
    _ = Cache.sadd(set_key(app_key, blocker), blocked)
    _ = Cache.set(loaded_key(app_key, blocker), "1")
    :ok = Invalidator.broadcast({:block, app_key, blocker})
    :ok = L1.put(L1.block_key(app_key, blocker, blocked), true)
    :ok
  end

  @doc "写穿：清除拉黑。"
  @spec delete(String.t(), String.t(), String.t()) :: :ok
  def delete(app_key, blocker, blocked) do
    _ = Cache.srem(set_key(app_key, blocker), blocked)
    _ = Cache.set(loaded_key(app_key, blocker), "1")
    :ok = Invalidator.broadcast({:block, app_key, blocker})
    :ok = L1.put(L1.block_key(app_key, blocker, blocked), false)
    :ok
  end

  @doc "任一方拉黑则不可消息（与 FriendStore.messaging_blocked? 语义一致）。"
  @spec messaging_blocked?(String.t(), String.t(), String.t()) :: boolean()
  def messaging_blocked?(app_key, from, to) do
    blocked?(app_key, from, to) or blocked?(app_key, to, from)
  end

  defp blocked_l2(app_key, blocker, blocked) do
    key = set_key(app_key, blocker)

    case loaded?(app_key, blocker) do
      true ->
        case Cache.sismember(key, blocked) do
          {:ok, hit?} -> {hit?, :l2}
          {:error, _} -> {pg_blocked?(app_key, blocker, blocked), :pg}
        end

      false ->
        warm(app_key, blocker)

        case Cache.sismember(key, blocked) do
          {:ok, hit?} -> {hit?, :pg}
          {:error, _} -> {pg_blocked?(app_key, blocker, blocked), :pg}
        end
    end
  end

  defp warm(app_key, blocker) do
    ids = FriendStore.list_blocked_user_ids(app_key, blocker)
    key = set_key(app_key, blocker)

    Enum.each(ids, fn id ->
      _ = Cache.sadd(key, id)
    end)

    _ = Cache.set(loaded_key(app_key, blocker), "1")
    :ok
  end

  defp loaded?(app_key, blocker) do
    case Cache.exists?(set_key(app_key, blocker)) do
      {:ok, true} ->
        true

      {:ok, false} ->
        case Cache.get(loaded_key(app_key, blocker)) do
          {:ok, "1"} -> true
          _ -> false
        end

      {:error, _} ->
        false
    end
  end

  defp pg_blocked?(app_key, blocker, blocked) do
    case FriendStore.get_friendship(app_key, blocker, blocked) do
      {:ok, %{status: "blocked"}} -> true
      _ -> false
    end
  end

  defp emit(type, true, layer), do: Telemetry.emit_check(type, :deny, layer)
  defp emit(type, false, layer), do: Telemetry.emit_check(type, :allow, layer)

  defp set_key(app_key, blocker), do: "im:block:#{app_key}:#{blocker}"
  defp loaded_key(app_key, blocker), do: "im:block:#{app_key}:#{blocker}:loaded"
end
