defmodule IM.Services.MsgId.Lease do
  @moduledoc """
  Snowflake `worker_id` 集群租约（DD-039）。

  Cache：`SET im:id:worker:{id} {node} NX EX 30`；每 10s 续期；PG `id_workers` 镜像。
  """

  alias IM.Cache
  alias IM.Stores.IdWorkerStore

  @max_worker_id 1023
  @ttl_sec 30
  @renew_ms 10_000

  @doc "租约 TTL（秒）。"
  def ttl_sec, do: @ttl_sec

  @doc "续期间隔（毫秒）。"
  def renew_ms, do: @renew_ms

  @doc """
  扫描并占用一个 `worker_id`。

  ## 示例

      {:ok, 7} = IM.Services.MsgId.Lease.acquire()
  """
  @spec acquire(String.t()) :: {:ok, non_neg_integer()} | {:error, :no_worker}
  def acquire(node_name \\ node_name()) when is_binary(node_name) do
    Enum.reduce_while(0..@max_worker_id, {:error, :no_worker}, fn id, _acc ->
      key = key(id)

      case Cache.set_nx(key, node_name, @ttl_sec) do
        {:ok, true} ->
          _ = mirror(id, node_name)
          {:halt, {:ok, id}}

        _ ->
          {:cont, {:error, :no_worker}}
      end
    end)
  end

  @doc "续期；仅当当前持有者为本节点时成功。"
  @spec renew(non_neg_integer(), String.t()) :: :ok | {:error, term()}
  def renew(worker_id, node_name \\ node_name())
      when is_integer(worker_id) and is_binary(node_name) do
    key = key(worker_id)

    case Cache.get(key) do
      {:ok, ^node_name} ->
        :ok = Cache.set_ex(key, node_name, @ttl_sec)
        _ = mirror(worker_id, node_name)
        :ok

      {:ok, _} ->
        {:error, :not_owner}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "释放租约。"
  @spec release(non_neg_integer(), String.t()) :: :ok
  def release(worker_id, node_name \\ node_name())
      when is_integer(worker_id) and is_binary(node_name) do
    key = key(worker_id)

    case Cache.get(key) do
      {:ok, ^node_name} ->
        _ = Cache.del(key)
        _ = IdWorkerStore.delete(worker_id)
        :ok

      _ ->
        :ok
    end
  end

  defp mirror(worker_id, node_name) do
    until =
      DateTime.utc_now()
      |> DateTime.add(@ttl_sec, :second)
      |> DateTime.truncate(:microsecond)

    case IdWorkerStore.upsert(worker_id, node_name, until) do
      :ok -> :ok
      {:error, _} -> :ok
    end
  end

  defp key(id), do: "im:id:worker:#{id}"

  defp node_name, do: Atom.to_string(Node.self())
end
