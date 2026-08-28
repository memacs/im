defmodule IM.Group.MetaCache do
  @moduledoc """
  群元数据热缓存（JSON → L2/Memory；变更时失效）。

  键：`im:group:meta:{app_key}:{group_id}`。
  """

  alias IM.Cache
  alias IM.Permission.Invalidator
  alias IM.Schemas.Group
  alias IM.Stores.GroupStore

  @fields ~w(app_key group_id name owner_uid member_count max_members storage_mode persist_msg announcement)a

  @doc "读取群元数据（与 GroupStore.get 等价）。"
  @spec get(String.t(), String.t()) :: {:ok, Group.t()} | {:error, :not_found}
  def get(app_key, group_id) when is_binary(app_key) and is_binary(group_id) do
    case Cache.get(meta_key(app_key, group_id)) do
      {:ok, json} when is_binary(json) ->
        case Jason.decode(json) do
          {:ok, map} -> {:ok, struct(Group, atomize(map))}
          _ -> fetch_and_cache(app_key, group_id)
        end

      _ ->
        fetch_and_cache(app_key, group_id)
    end
  end

  @doc "写穿更新缓存。"
  @spec put(Group.t()) :: :ok
  def put(%Group{} = group) do
    _ = Cache.set(meta_key(group.app_key, group.group_id), encode(group))
    :ok
  end

  @doc "失效群元数据缓存。"
  @spec invalidate(String.t(), String.t()) :: :ok
  def invalidate(app_key, group_id) do
    _ = Cache.del(meta_key(app_key, group_id))
    :ok = Invalidator.broadcast({:group_meta, app_key, group_id})
    :ok
  end

  defp fetch_and_cache(app_key, group_id) do
    case GroupStore.get(app_key, group_id) do
      {:ok, group} = ok ->
        _ = Cache.set(meta_key(app_key, group_id), encode(group))
        ok

      {:error, :not_found} = err ->
        err
    end
  end

  defp encode(%Group{} = group) do
    group
    |> Map.from_struct()
    |> Map.take(@fields)
    |> Jason.encode!()
  end

  defp atomize(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      {if(is_binary(k), do: String.to_existing_atom(k), else: k), v}
    end)
  rescue
    ArgumentError ->
      Map.new(map, fn {k, v} -> {String.to_atom(k), v} end)
  end

  defp meta_key(app_key, group_id), do: "im:group:meta:#{app_key}:#{group_id}"
end
