defmodule IM.Cache.Redis do
  @moduledoc """
  Redix 实现（P9-02）。经 `IM.Cache` 使用，Service 不直接依赖 Redix。
  """

  @behaviour IM.Cache

  @conn IM.Cache.Redis.Conn

  @impl true
  def incr(key) do
    case Redix.command(@conn, ["INCR", key]) do
      {:ok, n} when is_integer(n) -> {:ok, n}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def get(key) do
    case Redix.command(@conn, ["GET", key]) do
      {:ok, nil} -> {:ok, nil}
      {:ok, val} when is_binary(val) -> {:ok, val}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def set(key, value) do
    case Redix.command(@conn, ["SET", key, value]) do
      {:ok, "OK"} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def set_nx(key, value, ttl_sec)
      when is_binary(key) and is_binary(value) and is_integer(ttl_sec) and ttl_sec > 0 do
    case Redix.command(@conn, ["SET", key, value, "NX", "EX", ttl_sec]) do
      {:ok, "OK"} -> {:ok, true}
      {:ok, nil} -> {:ok, false}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def set_ex(key, value, ttl_sec)
      when is_binary(key) and is_binary(value) and is_integer(ttl_sec) and ttl_sec > 0 do
    case Redix.command(@conn, ["SET", key, value, "EX", ttl_sec]) do
      {:ok, "OK"} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def del(key) do
    case Redix.command(@conn, ["DEL", key]) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def exists?(key) do
    case Redix.command(@conn, ["EXISTS", key]) do
      {:ok, n} when is_integer(n) -> {:ok, n > 0}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def sadd(key, member) do
    case Redix.command(@conn, ["SADD", key, member]) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def srem(key, member) do
    case Redix.command(@conn, ["SREM", key, member]) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def sismember(key, member) do
    case Redix.command(@conn, ["SISMEMBER", key, member]) do
      {:ok, 1} -> {:ok, true}
      {:ok, 0} -> {:ok, false}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def smembers(key) do
    case Redix.command(@conn, ["SMEMBERS", key]) do
      {:ok, members} when is_list(members) -> {:ok, members}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def zadd(key, member, score) do
    case Redix.command(@conn, ["ZADD", key, to_string(score), member]) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def zrem(key, member) do
    case Redix.command(@conn, ["ZREM", key, member]) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def zscore(key, member) do
    case Redix.command(@conn, ["ZSCORE", key, member]) do
      {:ok, nil} ->
        {:ok, nil}

      {:ok, score} when is_binary(score) ->
        case Float.parse(score) do
          {n, _} -> {:ok, n}
          :error -> {:error, :bad_score}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
