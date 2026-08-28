defmodule IM.Room.MetaCache do
  @moduledoc "聊天室元数据热缓存。"

  alias IM.Cache
  alias IM.Permission.Invalidator
  alias IM.Schemas.Room
  alias IM.Stores.RoomStore

  @fields ~w(app_key room_id name owner_uid member_count persist_msg announcement)a

  @spec get(String.t(), String.t()) :: {:ok, Room.t()} | {:error, :not_found}
  def get(app_key, room_id) when is_binary(app_key) and is_binary(room_id) do
    case Cache.get(meta_key(app_key, room_id)) do
      {:ok, json} when is_binary(json) ->
        case Jason.decode(json) do
          {:ok, map} -> {:ok, struct(Room, atomize(map))}
          _ -> fetch_and_cache(app_key, room_id)
        end

      _ ->
        fetch_and_cache(app_key, room_id)
    end
  end

  @spec put(Room.t()) :: :ok
  def put(%Room{} = room) do
    _ = Cache.set(meta_key(room.app_key, room.room_id), encode(room))
    :ok
  end

  @spec invalidate(String.t(), String.t()) :: :ok
  def invalidate(app_key, room_id) do
    _ = Cache.del(meta_key(app_key, room_id))
    :ok = Invalidator.broadcast({:room_meta, app_key, room_id})
    :ok
  end

  defp fetch_and_cache(app_key, room_id) do
    case RoomStore.get(app_key, room_id) do
      {:ok, room} = ok ->
        _ = Cache.set(meta_key(app_key, room_id), encode(room))
        ok

      {:error, :not_found} = err ->
        err
    end
  end

  defp encode(%Room{} = room) do
    room |> Map.from_struct() |> Map.take(@fields) |> Jason.encode!()
  end

  defp atomize(map) when is_map(map) do
    Enum.reduce(@fields, %{}, fn field, acc ->
      key = Atom.to_string(field)

      case Map.get(map, key) || Map.get(map, field) do
        nil -> acc
        v -> Map.put(acc, field, v)
      end
    end)
  end

  defp meta_key(app_key, room_id), do: "im:room:meta:#{app_key}:#{room_id}"
end
