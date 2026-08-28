defmodule IM.Permission.MuteCache do
  @moduledoc """
  群禁言热缓存（DD-033）。L1 → L2 ZSET（score = muted_until ms）。
  """

  alias IM.Cache
  alias IM.Permission.{Invalidator, L1, Telemetry}
  alias IM.Stores.GroupStore

  @doc "成员当前是否处于禁言期。"
  @spec muted?(String.t(), String.t(), String.t(), non_neg_integer()) :: boolean()
  def muted?(app_key, group_id, user_id, now_ms \\ System.system_time(:millisecond))
      when is_binary(app_key) and is_binary(group_id) and is_binary(user_id) do
    l1 = L1.mute_key(app_key, group_id, user_id)

    case L1.get(l1) do
      {:ok, hit?} ->
        emit(hit?, :l1)
        hit?

      :miss ->
        {hit?, layer} = muted_l2(app_key, group_id, user_id, now_ms)
        :ok = L1.put(l1, hit?)
        emit(hit?, layer)
        hit?
    end
  end

  @doc "写穿：设置禁言截止（ms）；`muted_until_ms == 0` 解除。"
  @spec put(String.t(), String.t(), String.t(), non_neg_integer()) :: :ok
  def put(app_key, group_id, user_id, muted_until_ms)
      when is_binary(app_key) and is_binary(group_id) and is_binary(user_id) and
             is_integer(muted_until_ms) and muted_until_ms >= 0 do
    key = zset_key(app_key, group_id)

    if muted_until_ms == 0 do
      _ = Cache.zrem(key, user_id)
    else
      _ = Cache.zadd(key, user_id, muted_until_ms)
    end

    _ = Cache.set(loaded_key(app_key, group_id), "1")
    now = System.system_time(:millisecond)
    muted? = muted_until_ms > now
    :ok = Invalidator.broadcast({:mute, app_key, group_id})
    :ok = L1.put(L1.mute_key(app_key, group_id, user_id), muted?)
    :ok
  end

  defp muted_l2(app_key, group_id, user_id, now_ms) do
    key = zset_key(app_key, group_id)

    case loaded?(app_key, group_id) do
      true ->
        {score_muted?(key, user_id, now_ms), :l2}

      false ->
        warm(app_key, group_id, now_ms)
        {score_muted?(key, user_id, now_ms), :pg}
    end
  end

  defp emit(true, layer), do: Telemetry.emit_check(:mute, :deny, layer)
  defp emit(false, layer), do: Telemetry.emit_check(:mute, :allow, layer)

  defp score_muted?(key, user_id, now_ms) do
    case Cache.zscore(key, user_id) do
      {:ok, score} when is_number(score) ->
        until = trunc(score)

        if until > now_ms do
          true
        else
          _ = Cache.zrem(key, user_id)
          false
        end

      {:ok, nil} ->
        false

      {:error, _} ->
        false
    end
  end

  defp warm(app_key, group_id, now_ms) do
    key = zset_key(app_key, group_id)

    Enum.each(GroupStore.list_active_mutes(app_key, group_id, now_ms), fn {uid, until} ->
      _ = Cache.zadd(key, uid, until)
    end)

    _ = Cache.set(loaded_key(app_key, group_id), "1")
    :ok
  end

  defp loaded?(app_key, group_id) do
    case Cache.exists?(zset_key(app_key, group_id)) do
      {:ok, true} ->
        true

      {:ok, false} ->
        case Cache.get(loaded_key(app_key, group_id)) do
          {:ok, "1"} -> true
          _ -> false
        end

      {:error, _} ->
        false
    end
  end

  defp zset_key(app_key, group_id), do: "im:mute:#{app_key}:#{group_id}"
  defp loaded_key(app_key, group_id), do: "im:mute:#{app_key}:#{group_id}:loaded"
end
