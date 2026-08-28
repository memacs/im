defmodule IM.Room.MemberCache do
  @moduledoc """
  聊天室成员热缓存（L1 → L2 SET → PG）。
  """

  alias IM.Cache
  alias IM.Permission.{Invalidator, L1}
  alias IM.Stores.RoomStore

  @spec member?(String.t(), String.t(), String.t()) :: boolean()
  def member?(app_key, room_id, user_id)
      when is_binary(app_key) and is_binary(room_id) and is_binary(user_id) do
    l1 = L1.room_member_key(app_key, room_id, user_id)

    case L1.get(l1) do
      {:ok, hit?} ->
        hit?

      :miss ->
        hit? = member_l2(app_key, room_id, user_id)
        :ok = L1.put(l1, hit?)
        hit?
    end
  end

  @spec put_member(String.t(), String.t(), String.t()) :: :ok
  def put_member(app_key, room_id, user_id) do
    _ = Cache.sadd(set_key(app_key, room_id), user_id)
    _ = Cache.set(loaded_key(app_key, room_id), "1")
    :ok = L1.put(L1.room_member_key(app_key, room_id, user_id), true)
    :ok
  end

  @spec remove_member(String.t(), String.t(), String.t()) :: :ok
  def remove_member(app_key, room_id, user_id) do
    _ = Cache.srem(set_key(app_key, room_id), user_id)
    _ = Cache.set(loaded_key(app_key, room_id), "1")
    :ok = L1.put(L1.room_member_key(app_key, room_id, user_id), false)
    :ok
  end

  @spec invalidate(String.t(), String.t()) :: :ok
  def invalidate(app_key, room_id) do
    _ = Cache.del(set_key(app_key, room_id))
    _ = Cache.del(loaded_key(app_key, room_id))
    :ok = Invalidator.broadcast({:room_members, app_key, room_id})
    :ok
  end

  defp member_l2(app_key, room_id, user_id) do
    if loaded?(app_key, room_id) do
      case Cache.sismember(set_key(app_key, room_id), user_id) do
        {:ok, hit?} -> hit?
        {:error, _} -> RoomStore.member?(app_key, room_id, user_id)
      end
    else
      warm(app_key, room_id)

      case Cache.sismember(set_key(app_key, room_id), user_id) do
        {:ok, hit?} -> hit?
        {:error, _} -> RoomStore.member?(app_key, room_id, user_id)
      end
    end
  end

  defp warm(app_key, room_id) do
    ids = RoomStore.list_member_ids(app_key, room_id)
    key = set_key(app_key, room_id)
    Enum.each(ids, &Cache.sadd(key, &1))
    _ = Cache.set(loaded_key(app_key, room_id), "1")
    :ok
  end

  defp loaded?(app_key, room_id) do
    case Cache.exists?(set_key(app_key, room_id)) do
      {:ok, true} -> true
      {:ok, false} -> match?({:ok, "1"}, Cache.get(loaded_key(app_key, room_id)))
      {:error, _} -> false
    end
  end

  defp set_key(app_key, room_id), do: "im:room:members:#{app_key}:#{room_id}"
  defp loaded_key(app_key, room_id), do: "im:room:members:#{app_key}:#{room_id}:loaded"
end
