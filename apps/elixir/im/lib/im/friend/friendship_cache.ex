defmodule IM.Friend.FriendshipCache do
  @moduledoc """
  好友关系（accepted）热缓存：L1 → L2 → PG。

  键：`im:friend:{app}:{user_id}:{friend_user_id}`，值 `1`/`0`。
  """

  alias IM.Cache
  alias IM.Permission.{Invalidator, L1}
  alias IM.Stores.FriendStore

  @doc "双方是否为 accepted 好友（与 Friend.friends? 语义一致）。"
  @spec friends?(String.t(), String.t(), String.t()) :: boolean()
  def friends?(app_key, user_a, user_b)
      when is_binary(app_key) and is_binary(user_a) and is_binary(user_b) do
    l1 = L1.friendship_key(app_key, user_a, user_b)

    case L1.get(l1) do
      {:ok, hit?} ->
        hit?

      :miss ->
        hit? = friends_l2(app_key, user_a, user_b)
        :ok = L1.put(l1, hit?)
        hit?
    end
  end

  @doc "写穿：标记为好友。"
  @spec put_accepted(String.t(), String.t(), String.t()) :: :ok
  def put_accepted(app_key, user_id, friend_user_id) do
    _ = Cache.set(cache_key(app_key, user_id, friend_user_id), "1")
    :ok = L1.put(L1.friendship_key(app_key, user_id, friend_user_id), true)
    :ok = Invalidator.broadcast({:friendship, app_key, user_id, friend_user_id})
    :ok
  end

  @doc "写穿：标记非好友。"
  @spec put_not_friend(String.t(), String.t(), String.t()) :: :ok
  def put_not_friend(app_key, user_id, friend_user_id) do
    _ = Cache.set(cache_key(app_key, user_id, friend_user_id), "0")
    :ok = L1.put(L1.friendship_key(app_key, user_id, friend_user_id), false)
    :ok = Invalidator.broadcast({:friendship, app_key, user_id, friend_user_id})
    :ok
  end

  @doc "双向失效。"
  @spec invalidate_pair(String.t(), String.t(), String.t()) :: :ok
  def invalidate_pair(app_key, user_a, user_b) do
    _ = Cache.del(cache_key(app_key, user_a, user_b))
    _ = Cache.del(cache_key(app_key, user_b, user_a))
    :ok = Invalidator.broadcast({:friendship, app_key, user_a, user_b})
    :ok = Invalidator.broadcast({:friendship, app_key, user_b, user_a})
    :ok
  end

  defp friends_l2(app_key, user_a, user_b) do
    case Cache.get(cache_key(app_key, user_a, user_b)) do
      {:ok, "1"} ->
        true

      {:ok, "0"} ->
        false

      _ ->
        pg_friends?(app_key, user_a, user_b)
    end
  end

  defp pg_friends?(app_key, user_a, user_b) do
    hit? =
      case FriendStore.get_friendship(app_key, user_a, user_b) do
        {:ok, %{status: "accepted"}} -> true
        _ -> false
      end

    _ = Cache.set(cache_key(app_key, user_a, user_b), if(hit?, do: "1", else: "0"))
    hit?
  end

  defp cache_key(app_key, user_id, friend_user_id),
    do: "im:friend:#{app_key}:#{user_id}:#{friend_user_id}"
end
