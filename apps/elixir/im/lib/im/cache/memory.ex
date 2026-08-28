defmodule IM.Cache.Memory do
  @moduledoc """
  进程内 ETS 缓存（测试 / 无 Redis 时默认）。
  """

  @behaviour IM.Cache

  @table :im_cache_memory

  @doc "确保 ETS 表存在。"
  @spec ensure_table!() :: :ok
  def ensure_table! do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
        :ok

      _ ->
        :ok
    end
  end

  @doc "清空（测试用）。"
  @spec reset!() :: :ok
  def reset! do
    ensure_table!()
    true = :ets.delete_all_objects(@table)
    :ok
  end

  @impl true
  def incr(key) do
    ensure_table!()

    case read_string(key) do
      {:ok, val} when is_binary(val) ->
        next = String.to_integer(val) + 1
        true = :ets.insert(@table, {key, Integer.to_string(next)})
        {:ok, next}

      {:ok, nil} ->
        true = :ets.insert(@table, {key, "1"})
        {:ok, 1}

      {:error, _} = err ->
        err
    end
  end

  @impl true
  def get(key) do
    ensure_table!()
    read_string(key)
  end

  @impl true
  def set(key, value) do
    ensure_table!()
    true = :ets.insert(@table, {key, value})
    :ok
  end

  @impl true
  def set_nx(key, value, ttl_sec)
      when is_binary(key) and is_binary(value) and is_integer(ttl_sec) and ttl_sec > 0 do
    ensure_table!()

    case read_raw(key) do
      {:ok, :missing} ->
        expire_at = System.system_time(:second) + ttl_sec
        true = :ets.insert(@table, {key, {value, expire_at}})
        {:ok, true}

      {:ok, _} ->
        {:ok, false}
    end
  end

  @impl true
  def set_ex(key, value, ttl_sec)
      when is_binary(key) and is_binary(value) and is_integer(ttl_sec) and ttl_sec > 0 do
    ensure_table!()
    expire_at = System.system_time(:second) + ttl_sec
    true = :ets.insert(@table, {key, {value, expire_at}})
    :ok
  end

  @impl true
  def del(key) do
    ensure_table!()
    true = :ets.delete(@table, key)
    :ok
  end

  @impl true
  def exists?(key) do
    ensure_table!()

    case read_raw(key) do
      {:ok, :missing} -> {:ok, false}
      {:ok, _} -> {:ok, true}
    end
  end

  @impl true
  def sadd(key, member) do
    ensure_table!()

    set =
      case read_raw(key) do
        {:ok, {:set, s}} -> s
        {:ok, :missing} -> MapSet.new()
        {:ok, _} -> :wrong_type
      end

    if set == :wrong_type do
      {:error, :wrong_type}
    else
      true = :ets.insert(@table, {key, {:set, MapSet.put(set, member)}})
      :ok
    end
  end

  @impl true
  def srem(key, member) do
    ensure_table!()

    case read_raw(key) do
      {:ok, {:set, s}} ->
        true = :ets.insert(@table, {key, {:set, MapSet.delete(s, member)}})
        :ok

      {:ok, :missing} ->
        :ok

      {:ok, _} ->
        {:error, :wrong_type}
    end
  end

  @impl true
  def sismember(key, member) do
    ensure_table!()

    case read_raw(key) do
      {:ok, {:set, s}} -> {:ok, MapSet.member?(s, member)}
      {:ok, :missing} -> {:ok, false}
      {:ok, _} -> {:error, :wrong_type}
    end
  end

  @impl true
  def smembers(key) do
    ensure_table!()

    case read_raw(key) do
      {:ok, {:set, s}} -> {:ok, MapSet.to_list(s)}
      {:ok, :missing} -> {:ok, []}
      {:ok, _} -> {:error, :wrong_type}
    end
  end

  @impl true
  def zadd(key, member, score) do
    ensure_table!()

    z =
      case read_raw(key) do
        {:ok, {:zset, m}} -> m
        {:ok, :missing} -> %{}
        {:ok, _} -> :wrong_type
      end

    if z == :wrong_type do
      {:error, :wrong_type}
    else
      true = :ets.insert(@table, {key, {:zset, Map.put(z, member, score)}})
      :ok
    end
  end

  @impl true
  def zrem(key, member) do
    ensure_table!()

    case read_raw(key) do
      {:ok, {:zset, m}} ->
        true = :ets.insert(@table, {key, {:zset, Map.delete(m, member)}})
        :ok

      {:ok, :missing} ->
        :ok

      {:ok, _} ->
        {:error, :wrong_type}
    end
  end

  @impl true
  def zscore(key, member) do
    ensure_table!()

    case read_raw(key) do
      {:ok, {:zset, m}} -> {:ok, Map.get(m, member)}
      {:ok, :missing} -> {:ok, nil}
      {:ok, _} -> {:error, :wrong_type}
    end
  end

  defp read_string(key) do
    case read_raw(key) do
      {:ok, :missing} -> {:ok, nil}
      {:ok, val} when is_binary(val) -> {:ok, val}
      {:ok, _} -> {:error, :wrong_type}
    end
  end

  defp read_raw(key) do
    case :ets.lookup(@table, key) do
      [{^key, {val, exp}}] when is_binary(val) and is_integer(exp) ->
        if exp > System.system_time(:second) do
          {:ok, val}
        else
          true = :ets.delete(@table, key)
          {:ok, :missing}
        end

      [{^key, val}] when is_integer(val) ->
        {:ok, Integer.to_string(val)}

      [{^key, val}] when is_binary(val) ->
        {:ok, val}

      [{^key, {:set, _} = v}] ->
        {:ok, v}

      [{^key, {:zset, _} = v}] ->
        {:ok, v}

      [] ->
        {:ok, :missing}
    end
  end
end
