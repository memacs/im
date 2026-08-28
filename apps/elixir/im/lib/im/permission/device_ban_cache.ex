defmodule IM.Permission.DeviceBanCache do
  @moduledoc """
  设备封禁热缓存（DD-033）。L1 → L2 STRING。
  """

  alias IM.Cache
  alias IM.Domain.Error
  alias IM.Permission.{Invalidator, L1, Telemetry}
  alias IM.Stores.UserDeviceStore

  @doc "设备是否封禁。"
  @spec banned?(String.t(), String.t(), String.t()) :: boolean()
  def banned?(app_key, user_id, device_id)
      when is_binary(app_key) and is_binary(user_id) and is_binary(device_id) do
    l1 = L1.device_ban_key(app_key, user_id, device_id)

    case L1.get(l1) do
      {:ok, hit?} ->
        emit(hit?, :l1)
        hit?

      :miss ->
        {hit?, layer} = banned_l2(app_key, user_id, device_id)
        :ok = L1.put(l1, hit?)
        emit(hit?, layer)
        hit?
    end
  end

  @doc "未封禁返回 `:ok`，否则 `{:error, Error}`。"
  @spec ensure_allowed(String.t(), String.t(), String.t()) :: :ok | {:error, Error.t()}
  def ensure_allowed(app_key, user_id, device_id) do
    if banned?(app_key, user_id, device_id) do
      {:error, Error.new(:unauthorized, "device_banned")}
    else
      :ok
    end
  end

  @doc "写穿：标记封禁。"
  @spec put(String.t(), String.t(), String.t()) :: :ok
  def put(app_key, user_id, device_id) do
    _ = Cache.set(key(app_key, user_id, device_id), "1")
    :ok = Invalidator.broadcast({:device_ban, app_key, user_id, device_id})
    :ok = L1.put(L1.device_ban_key(app_key, user_id, device_id), true)
    :ok
  end

  @doc "写穿：清除封禁。"
  @spec delete(String.t(), String.t(), String.t()) :: :ok
  def delete(app_key, user_id, device_id) do
    _ = Cache.set(key(app_key, user_id, device_id), "0")
    :ok = Invalidator.broadcast({:device_ban, app_key, user_id, device_id})
    :ok = L1.put(L1.device_ban_key(app_key, user_id, device_id), false)
    :ok
  end

  defp banned_l2(app_key, user_id, device_id) do
    case Cache.get(key(app_key, user_id, device_id)) do
      {:ok, "1"} -> {true, :l2}
      {:ok, "0"} -> {false, :l2}
      {:ok, nil} -> {warm(app_key, user_id, device_id), :pg}
      {:error, _} -> {pg_banned?(app_key, user_id, device_id), :pg}
    end
  end

  defp warm(app_key, user_id, device_id) do
    hit? = pg_banned?(app_key, user_id, device_id)
    _ = Cache.set(key(app_key, user_id, device_id), if(hit?, do: "1", else: "0"))
    hit?
  end

  defp emit(true, layer), do: Telemetry.emit_check(:device_ban, :deny, layer)
  defp emit(false, layer), do: Telemetry.emit_check(:device_ban, :allow, layer)

  defp pg_banned?(app_key, user_id, device_id) do
    case UserDeviceStore.get(app_key, user_id, device_id) do
      {:ok, %{banned_at: banned}} when not is_nil(banned) -> true
      _ -> false
    end
  end

  defp key(app_key, user_id, device_id), do: "im:device_ban:#{app_key}:#{user_id}:#{device_id}"
end
