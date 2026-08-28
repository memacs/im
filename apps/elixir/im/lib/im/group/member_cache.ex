defmodule IM.Group.MemberCache do
  @moduledoc """
  群成员热缓存（L1 → L2 SET → PG）。

  键：`im:group:members:{app_key}:{group_id}`。
  """

  alias IM.Cache
  alias IM.Permission.{Invalidator, L1}
  alias IM.Stores.GroupStore

  @doc "是否为群成员。"
  @spec member?(String.t(), String.t(), String.t()) :: boolean()
  def member?(app_key, group_id, user_id)
      when is_binary(app_key) and is_binary(group_id) and is_binary(user_id) do
    l1 = L1.group_member_key(app_key, group_id, user_id)

    case L1.get(l1) do
      {:ok, hit?} ->
        hit?

      :miss ->
        hit? = member_l2(app_key, group_id, user_id)
        :ok = L1.put(l1, hit?)
        hit?
    end
  end

  @doc "列出群成员 user_id。"
  @spec list_member_ids(String.t(), String.t()) :: [String.t()]
  def list_member_ids(app_key, group_id) when is_binary(app_key) and is_binary(group_id) do
    if loaded?(app_key, group_id) do
      case Cache.smembers(set_key(app_key, group_id)) do
        {:ok, ids} -> ids
        {:error, _} -> GroupStore.list_member_ids(app_key, group_id)
      end
    else
      :ok = warm(app_key, group_id)

      case Cache.smembers(set_key(app_key, group_id)) do
        {:ok, ids} -> ids
        {:error, _} -> GroupStore.list_member_ids(app_key, group_id)
      end
    end
  end

  @doc "写穿：新增成员。"
  @spec add_members(String.t(), String.t(), [String.t()]) :: :ok
  def add_members(app_key, group_id, user_ids) when is_list(user_ids) do
    key = set_key(app_key, group_id)

    Enum.each(user_ids, fn uid ->
      _ = Cache.sadd(key, uid)
      :ok = L1.put(L1.group_member_key(app_key, group_id, uid), true)
    end)

    _ = Cache.set(loaded_key(app_key, group_id), "1")
    :ok
  end

  @doc "写穿：移除成员。"
  @spec remove_members(String.t(), String.t(), [String.t()]) :: :ok
  def remove_members(app_key, group_id, user_ids) when is_list(user_ids) do
    key = set_key(app_key, group_id)

    Enum.each(user_ids, fn uid ->
      _ = Cache.srem(key, uid)
      :ok = L1.put(L1.group_member_key(app_key, group_id, uid), false)
    end)

    _ = Cache.set(loaded_key(app_key, group_id), "1")
    :ok
  end

  @doc "失效整群成员缓存（解散等）。"
  @spec invalidate(String.t(), String.t()) :: :ok
  def invalidate(app_key, group_id) do
    _ = Cache.del(set_key(app_key, group_id))
    _ = Cache.del(loaded_key(app_key, group_id))
    :ok = Invalidator.broadcast({:group_members, app_key, group_id})
    :ok
  end

  @doc "建群后预热成员 SET。"
  @spec warm(String.t(), String.t()) :: :ok
  def warm(app_key, group_id) do
    ids = GroupStore.list_member_ids(app_key, group_id)
    key = set_key(app_key, group_id)

    Enum.each(ids, fn uid ->
      _ = Cache.sadd(key, uid)
    end)

    _ = Cache.set(loaded_key(app_key, group_id), "1")
    :ok
  end

  defp member_l2(app_key, group_id, user_id) do
    if loaded?(app_key, group_id) do
      case Cache.sismember(set_key(app_key, group_id), user_id) do
        {:ok, hit?} -> hit?
        {:error, _} -> pg_member?(app_key, group_id, user_id)
      end
    else
      :ok = warm(app_key, group_id)

      case Cache.sismember(set_key(app_key, group_id), user_id) do
        {:ok, hit?} -> hit?
        {:error, _} -> pg_member?(app_key, group_id, user_id)
      end
    end
  end

  defp pg_member?(app_key, group_id, user_id) do
    GroupStore.member?(app_key, group_id, user_id)
  end

  defp loaded?(app_key, group_id) do
    case Cache.exists?(set_key(app_key, group_id)) do
      {:ok, true} -> true
      {:ok, false} -> loaded_flag?(app_key, group_id)
      {:error, _} -> false
    end
  end

  defp loaded_flag?(app_key, group_id) do
    case Cache.get(loaded_key(app_key, group_id)) do
      {:ok, "1"} -> true
      _ -> false
    end
  end

  defp set_key(app_key, group_id), do: "im:group:members:#{app_key}:#{group_id}"
  defp loaded_key(app_key, group_id), do: "im:group:members:#{app_key}:#{group_id}:loaded"
end
