defmodule IM.Cache do
  @moduledoc """
  缓存 Facade（P9-02）。

  业务只依赖本模块；实现经 `:im, :cache` 注入（默认 Memory；生产 Redis）。
  """

  @callback incr(String.t()) :: {:ok, integer()} | {:error, term()}
  @callback get(String.t()) :: {:ok, String.t() | nil} | {:error, term()}
  @callback set(String.t(), String.t()) :: :ok | {:error, term()}
  @callback set_nx(String.t(), String.t(), pos_integer()) :: {:ok, boolean()} | {:error, term()}
  @callback set_ex(String.t(), String.t(), pos_integer()) :: :ok | {:error, term()}
  @callback del(String.t()) :: :ok | {:error, term()}
  @callback exists?(String.t()) :: {:ok, boolean()} | {:error, term()}
  @callback sadd(String.t(), String.t()) :: :ok | {:error, term()}
  @callback srem(String.t(), String.t()) :: :ok | {:error, term()}
  @callback sismember(String.t(), String.t()) :: {:ok, boolean()} | {:error, term()}
  @callback smembers(String.t()) :: {:ok, [String.t()]} | {:error, term()}
  @callback zadd(String.t(), String.t(), number()) :: :ok | {:error, term()}
  @callback zrem(String.t(), String.t()) :: :ok | {:error, term()}
  @callback zscore(String.t(), String.t()) :: {:ok, number() | nil} | {:error, term()}

  @doc """
  原子自增，返回自增后的值。

  ## 示例

      {:ok, 1} = IM.Cache.incr("im:{a}:seq:conv:p:u1:u2")
  """
  @spec incr(String.t()) :: {:ok, integer()} | {:error, term()}
  def incr(key) when is_binary(key), do: impl().incr(key)

  @doc """
  读取字符串值；不存在返回 `{:ok, nil}`。

  ## 示例

      {:ok, nil} = IM.Cache.get("missing")
  """
  @spec get(String.t()) :: {:ok, String.t() | nil} | {:error, term()}
  def get(key) when is_binary(key), do: impl().get(key)

  @doc """
  写入字符串值。

  ## 示例

      :ok = IM.Cache.set("k", "1")
  """
  @spec set(String.t(), String.t()) :: :ok | {:error, term()}
  def set(key, value) when is_binary(key) and is_binary(value), do: impl().set(key, value)

  @doc """
  仅当 key 不存在时写入，并设置 TTL（秒）。成功占用返回 `{:ok, true}`。

  ## 示例

      {:ok, true} = IM.Cache.set_nx("im:id:worker:1", "node@host", 30)
  """
  @spec set_nx(String.t(), String.t(), pos_integer()) :: {:ok, boolean()} | {:error, term()}
  def set_nx(key, value, ttl_sec)
      when is_binary(key) and is_binary(value) and is_integer(ttl_sec) and ttl_sec > 0 do
    impl().set_nx(key, value, ttl_sec)
  end

  @doc """
  写入并设置 TTL（秒），覆盖已有值。

  ## 示例

      :ok = IM.Cache.set_ex("im:id:worker:1", "node@host", 30)
  """
  @spec set_ex(String.t(), String.t(), pos_integer()) :: :ok | {:error, term()}
  def set_ex(key, value, ttl_sec)
      when is_binary(key) and is_binary(value) and is_integer(ttl_sec) and ttl_sec > 0 do
    impl().set_ex(key, value, ttl_sec)
  end

  @doc """
  删除 key。

  ## 示例

      :ok = IM.Cache.del("im:id:worker:1")
  """
  @spec del(String.t()) :: :ok | {:error, term()}
  def del(key) when is_binary(key), do: impl().del(key)

  @doc """
  key 是否存在（含空 SET/ZSET）。

  ## 示例

      {:ok, false} = IM.Cache.exists?("missing")
  """
  @spec exists?(String.t()) :: {:ok, boolean()} | {:error, term()}
  def exists?(key) when is_binary(key), do: impl().exists?(key)

  @doc """
  SET 添加成员。

  ## 示例

      :ok = IM.Cache.sadd("im:block:a:u1", "u2")
  """
  @spec sadd(String.t(), String.t()) :: :ok | {:error, term()}
  def sadd(key, member) when is_binary(key) and is_binary(member), do: impl().sadd(key, member)

  @doc """
  SET 移除成员。
  """
  @spec srem(String.t(), String.t()) :: :ok | {:error, term()}
  def srem(key, member) when is_binary(key) and is_binary(member), do: impl().srem(key, member)

  @doc """
  SET 成员判断。
  """
  @spec sismember(String.t(), String.t()) :: {:ok, boolean()} | {:error, term()}
  def sismember(key, member) when is_binary(key) and is_binary(member) do
    impl().sismember(key, member)
  end

  @doc """
  SET 全部成员。
  """
  @spec smembers(String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def smembers(key) when is_binary(key), do: impl().smembers(key)

  @doc """
  ZSET 写入 score。
  """
  @spec zadd(String.t(), String.t(), number()) :: :ok | {:error, term()}
  def zadd(key, member, score)
      when is_binary(key) and is_binary(member) and is_number(score) do
    impl().zadd(key, member, score)
  end

  @doc """
  ZSET 移除成员。
  """
  @spec zrem(String.t(), String.t()) :: :ok | {:error, term()}
  def zrem(key, member) when is_binary(key) and is_binary(member), do: impl().zrem(key, member)

  @doc """
  ZSET 读取 score；不存在返回 `{:ok, nil}`。
  """
  @spec zscore(String.t(), String.t()) :: {:ok, number() | nil} | {:error, term()}
  def zscore(key, member) when is_binary(key) and is_binary(member) do
    impl().zscore(key, member)
  end

  @doc """
  是否配置了可写缓存实现（非 nil）。
  """
  @spec enabled?() :: boolean()
  def enabled?, do: not is_nil(Application.get_env(:im, :cache))

  defp impl do
    Application.get_env(:im, :cache) || IM.Cache.Memory
  end
end
