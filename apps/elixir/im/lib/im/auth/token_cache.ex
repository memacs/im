defmodule IM.Auth.TokenCache do
  @moduledoc """
  访问令牌热缓存：`token_hash` → 行快照（短 TTL；PG 仍为权威）。

  - 正向键：`im:token:{hash}`，TTL = min(剩余有效期, 配置上限)
  - 吊销键：`im:token:revoked:{hash}`
  - 设备批量吊销：`im:token:dev_rev:{app}:{user}:{device}`（毫秒时间戳）
  """

  alias IM.Cache
  alias IM.Schemas.AccessToken

  @fields ~w(app_key user_id device_id token_hash expires_at revoked_at inserted_at)a
  @default_max_ttl_sec 60
  @revoked_marker_ttl_sec 86_400
  @device_rev_ttl_sec 7 * 86_400

  @doc """
  读取缓存行；`:miss` 表示未命中；`{:error, :revoked}` 表示吊销键命中。
  """
  @spec lookup(String.t()) :: {:ok, AccessToken.t()} | {:error, :revoked} | :miss
  def lookup(token_hash) when is_binary(token_hash) do
    cond do
      revoked?(token_hash) ->
        {:error, :revoked}

      true ->
        case Cache.get(token_key(token_hash)) do
          {:ok, json} when is_binary(json) and json != "" ->
            case decode(json) do
              {:ok, row} ->
                if device_revoked?(row), do: :miss, else: {:ok, row}

              _ ->
                :miss
            end

          _ ->
            :miss
        end
    end
  end

  @doc "写穿有效 token（已校验未吊销且未过期）。"
  @spec put(AccessToken.t()) :: :ok
  def put(%AccessToken{revoked_at: nil} = row) do
    ttl = cache_ttl_sec(row.expires_at)

    if ttl > 0 do
      _ = Cache.set_ex(token_key(row.token_hash), encode(row), ttl)
    end

    :ok
  end

  def put(_), do: :ok

  @doc "吊销单 token：写 denylist 并删正向缓存。"
  @spec revoke_hash(String.t()) :: :ok
  def revoke_hash(token_hash) when is_binary(token_hash) do
    ttl = Application.get_env(:im, :token_revoked_marker_ttl_sec, @revoked_marker_ttl_sec)
    _ = Cache.set_ex(revoked_key(token_hash), "1", ttl)
    _ = Cache.del(token_key(token_hash))
    :ok
  end

  @doc "吊销设备全部 token：记录设备吊销时间戳，使已缓存 token 失效。"
  @spec revoke_device(String.t(), String.t(), String.t()) :: :ok
  def revoke_device(app_key, user_id, device_id)
      when is_binary(app_key) and is_binary(user_id) and is_binary(device_id) do
    now_ms = System.system_time(:millisecond)
    ttl = Application.get_env(:im, :token_device_rev_ttl_sec, @device_rev_ttl_sec)

    _ =
      Cache.set_ex(
        device_rev_key(app_key, user_id, device_id),
        Integer.to_string(now_ms),
        ttl
      )

    :ok
  end

  defp revoked?(token_hash) do
    case Cache.get(revoked_key(token_hash)) do
      {:ok, "1"} -> true
      _ -> false
    end
  end

  defp device_revoked?(%AccessToken{} = row) do
    issued_ms = DateTime.to_unix(row.inserted_at, :millisecond)

    case Cache.get(device_rev_key(row.app_key, row.user_id, row.device_id)) do
      {:ok, ts} when is_binary(ts) ->
        case Integer.parse(ts) do
          {rev_ms, _} -> rev_ms >= issued_ms
          :error -> false
        end

      _ ->
        false
    end
  end

  defp cache_ttl_sec(expires_at) do
    max_ttl = Application.get_env(:im, :token_cache_max_ttl_sec, @default_max_ttl_sec)
    now = DateTime.utc_now()

    remaining =
      case DateTime.compare(expires_at, now) do
        :gt -> max(0, DateTime.diff(expires_at, now, :second))
        _ -> 0
      end

    min(remaining, max_ttl)
  end

  defp encode(%AccessToken{} = row) do
    row
    |> Map.from_struct()
    |> Map.take(@fields)
    |> Map.new(fn
      {k, %DateTime{} = dt} -> {k, DateTime.to_iso8601(dt)}
      {k, v} -> {k, v}
    end)
    |> Jason.encode!()
  end

  defp decode(json) do
    with {:ok, map} <- Jason.decode(json),
         {:ok, attrs} <- build_attrs(map) do
      {:ok, struct(AccessToken, attrs)}
    else
      _ -> :error
    end
  end

  defp build_attrs(map) when is_map(map) do
    attrs =
      Map.new(map, fn {k, v} ->
        atom =
          if is_binary(k) do
            String.to_existing_atom(k)
          else
            k
          end

        {atom, cast_field(atom, v)}
      end)

    {:ok, attrs}
  rescue
    ArgumentError -> :error
  end

  defp cast_field(field, v) when field in [:expires_at, :revoked_at, :inserted_at] do
    case v do
      nil ->
        nil

      %DateTime{} = dt ->
        dt

      bin when is_binary(bin) ->
        case DateTime.from_iso8601(bin) do
          {:ok, dt, _} -> dt
          _ -> nil
        end
    end
  end

  defp cast_field(_field, v), do: v

  defp token_key(hash), do: "im:token:#{hash}"
  defp revoked_key(hash), do: "im:token:revoked:#{hash}"

  defp device_rev_key(app_key, user_id, device_id),
    do: "im:token:dev_rev:#{app_key}:#{user_id}:#{device_id}"
end
