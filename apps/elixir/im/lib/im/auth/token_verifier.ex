defmodule IM.Auth.TokenVerifier do
  @moduledoc "默认 Token 校验：hash → revoked/expires → 设备封禁。"

  @behaviour IM.Auth

  alias IM.Auth.Token
  alias IM.Auth.TokenCache
  alias IM.Domain.Error
  alias IM.Permission.DeviceBanCache
  alias IM.Stores.{AccessTokenStore, UserDeviceStore}

  @impl IM.Auth
  def verify_token(token) when is_binary(token) and token != "" do
    hash = Token.hash(token)

    with {:ok, row} <- fetch_token(hash),
         :ok <- ensure_not_revoked(row),
         :ok <- ensure_not_expired(row),
         {:ok, _device} <- UserDeviceStore.get(row.app_key, row.user_id, row.device_id),
         :ok <- DeviceBanCache.ensure_allowed(row.app_key, row.user_id, row.device_id) do
      {:ok,
       %{
         app_key: row.app_key,
         user_id: row.user_id,
         device_id: row.device_id,
         token_hash: row.token_hash,
         expires_at: row.expires_at
       }}
    end
  end

  def verify_token(_), do: {:error, Error.new(:unauthorized, "empty token")}

  defp fetch_token(hash) do
    case TokenCache.lookup(hash) do
      {:ok, row} ->
        {:ok, row}

      {:error, :revoked} ->
        {:error, Error.new(:unauthorized, "token revoked")}

      :miss ->
        case AccessTokenStore.get_by_hash(hash) do
          {:ok, %{} = row} = ok ->
            if row.revoked_at == nil and not expired?(row) do
              :ok = TokenCache.put(row)
            end

            ok

          {:error, %Error{}} = err ->
            err
        end
    end
  end

  defp expired?(%{expires_at: expires_at}) do
    DateTime.compare(expires_at, DateTime.utc_now()) != :gt
  end

  defp ensure_not_revoked(%{revoked_at: nil}), do: :ok
  defp ensure_not_revoked(_), do: {:error, Error.new(:unauthorized, "token revoked")}

  defp ensure_not_expired(%{expires_at: expires_at}) do
    if DateTime.compare(expires_at, DateTime.utc_now()) == :gt do
      :ok
    else
      {:error, Error.new(:unauthorized, "token expired")}
    end
  end
end
