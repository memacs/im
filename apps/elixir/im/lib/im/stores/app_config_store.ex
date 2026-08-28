defmodule IM.Stores.AppConfigStore do
  @moduledoc "租户 `app_configs` 读写；进程内 ETS 缓存。"

  alias IM.Domain.Error
  alias IM.Repo
  alias IM.Schemas.AppConfig

  @table :im_app_config_cache

  @doc "确保 ETS 缓存表存在。"
  def ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])

      _ ->
        @table
    end

    :ok
  end

  @doc "写入配置（upsert）。`value` 可为 boolean / integer / string / map。"
  @spec put(String.t(), String.t(), String.t(), term(), keyword()) ::
          {:ok, AppConfig.t()} | {:error, Error.t()}
  def put(app_key, category, key, value, opts \\ []) do
    ensure_table()
    {encoded, type} = encode_value(value)
    description = Keyword.get(opts, :description)

    attrs = %{
      app_key: app_key,
      category: category,
      config_key: key,
      config_value: encoded,
      value_type: type,
      description: description
    }

    result =
      case get_row(app_key, category, key) do
        {:ok, row} ->
          row |> AppConfig.changeset(attrs) |> Repo.update()

        :error ->
          %AppConfig{} |> AppConfig.changeset(attrs) |> Repo.insert()
      end

    case result do
      {:ok, row} ->
        cache_put(row)
        :ok = IM.AppConfig.Invalidator.broadcast(row.app_key, row.category, row.config_key)
        {:ok, row}

      {:error, cs} ->
        {:error, Error.new(:internal_error, "app_config: #{inspect(cs.errors)}")}
    end
  end

  @doc "读取布尔配置；缺省返回 `default`。"
  @spec get_boolean(String.t(), String.t(), String.t(), boolean()) :: boolean()
  def get_boolean(app_key, category, key, default \\ false) do
    case get(app_key, category, key) do
      {:ok, v} when is_boolean(v) -> v
      {:ok, "true"} -> true
      {:ok, "false"} -> false
      {:ok, 1} -> true
      {:ok, 0} -> false
      _ -> default
    end
  end

  @doc "读取配置原始解码值。"
  @spec get(String.t(), String.t(), String.t()) :: {:ok, term()} | :error
  def get(app_key, category, key) do
    ensure_table()
    cache_key = {app_key, category, key}

    case :ets.lookup(@table, cache_key) do
      [{^cache_key, value}] ->
        {:ok, value}

      [] ->
        case get_row(app_key, category, key) do
          {:ok, row} ->
            value = decode_value(row)
            cache_put(row)
            {:ok, value}

          :error ->
            :error
        end
    end
  end

  @doc "测试辅助：清缓存。"
  def clear_cache do
    ensure_table()
    :ets.delete_all_objects(@table)
    :ok
  end

  @doc "删除单条 ETS 缓存（跨节点失效由 Invalidator 调用）。"
  @spec invalidate_local(String.t(), String.t(), String.t()) :: :ok
  def invalidate_local(app_key, category, key)
      when is_binary(app_key) and is_binary(category) and is_binary(key) do
    ensure_table()
    :ets.delete(@table, {app_key, category, key})
    :ok
  end

  defp get_row(app_key, category, key) do
    case Repo.get_by(AppConfig, app_key: app_key, category: category, config_key: key) do
      nil -> :error
      row -> {:ok, row}
    end
  end

  defp cache_put(%AppConfig{} = row) do
    ensure_table()
    :ets.insert(@table, {{row.app_key, row.category, row.config_key}, decode_value(row)})
  end

  defp encode_value(true), do: {"true", "boolean"}
  defp encode_value(false), do: {"false", "boolean"}
  defp encode_value(n) when is_integer(n), do: {Integer.to_string(n), "integer"}
  defp encode_value(map) when is_map(map), do: {Jason.encode!(map), "json"}
  defp encode_value(bin) when is_binary(bin), do: {bin, "string"}
  defp encode_value(other), do: {inspect(other), "string"}

  defp decode_value(%AppConfig{value_type: "boolean", config_value: v}),
    do: v in ["true", "1", "TRUE"]

  defp decode_value(%AppConfig{value_type: "integer", config_value: v}) do
    case Integer.parse(v) do
      {n, _} -> n
      :error -> v
    end
  end

  defp decode_value(%AppConfig{value_type: "json", config_value: v}) do
    case Jason.decode(v) do
      {:ok, map} -> map
      _ -> v
    end
  end

  defp decode_value(%AppConfig{config_value: v}), do: v
end
