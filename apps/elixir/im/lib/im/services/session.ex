defmodule IM.Services.Session do
  @moduledoc """
  HTTP 登录 / 登出：校验密码、签发与吊销 access_token、返回连接配置。
  """

  alias IM.Auth.{Password, Token}
  alias IM.Domain.Error
  alias IM.Permission.DeviceBanCache
  alias IM.Stores.{AccessTokenStore, UserDeviceStore, UserStore}

  @doc """
  创建会话（登录）。

  ## 示例

      IM.Services.Session.create(%{
        "app_key" => "a",
        "user_id" => "u",
        "password" => "p",
        "device_id" => "d",
        "platform" => "ios",
        "sdk_ver" => "1.0"
      })
  """
  @spec create(map()) :: {:ok, map()} | {:error, Error.t()}
  def create(params) when is_map(params) do
    with {:ok, fields} <- cast_login(params),
         {:ok, user} <- UserStore.get(fields.app_key, fields.user_id),
         :ok <- ensure_user_enabled(user),
         :ok <- ensure_password(fields, user),
         :ok <- DeviceBanCache.ensure_allowed(fields.app_key, fields.user_id, fields.device_id),
         {:ok, device} <-
           UserDeviceStore.upsert(%{
             app_key: fields.app_key,
             user_id: fields.user_id,
             device_id: fields.device_id,
             platform: fields.platform,
             sdk_ver: fields.sdk_ver
           }),
         :ok <- ensure_not_banned(device),
         {:ok, plain, expires_at} <- issue_token(fields) do
      {:ok,
       %{
         access_token: plain,
         expires_at: DateTime.to_unix(expires_at, :millisecond),
         user_id: fields.user_id,
         clear_local_data: device.clear_local_data_pending,
         connection: %{
           websocket_urls: websocket_urls(),
           preferred_index: 0
         },
         config: connection_config()
       }}
    end
  end

  @doc """
  吊销当前 Bearer token（登出）。

  ## 示例

      IM.Services.Session.revoke(token_plain)
  """
  @spec revoke(String.t()) :: :ok | {:error, Error.t()}
  def revoke(token) when is_binary(token) do
    AccessTokenStore.revoke_hash(Token.hash(token))
  end

  defp cast_login(params) do
    required = ["app_key", "user_id", "password", "device_id", "platform", "sdk_ver"]

    missing = Enum.reject(required, &(present?(params[&1]) or present?(params[String.to_atom(&1)])))

    if missing != [] do
      {:error, Error.new(:msg_invalid, "missing fields: #{Enum.join(missing, ",")}")}
    else
      {:ok,
       %{
         app_key: fetch(params, "app_key"),
         user_id: fetch(params, "user_id"),
         password: fetch(params, "password"),
         device_id: fetch(params, "device_id"),
         platform: fetch(params, "platform"),
         sdk_ver: fetch(params, "sdk_ver")
       }}
    end
  end

  defp fetch(map, key) do
    Map.get(map, key) || Map.get(map, String.to_existing_atom(key)) || Map.get(map, String.to_atom(key))
  rescue
    ArgumentError -> Map.get(map, key)
  end

  defp present?(v), do: is_binary(v) and v != ""

  defp ensure_user_enabled(%{disabled_at: nil}), do: :ok
  defp ensure_user_enabled(_), do: {:error, Error.new(:unauthorized, "user_disabled")}

  defp ensure_password(fields, user) do
    if Password.verify(fields.password, fields.app_key, fields.user_id, user.password_hash) do
      :ok
    else
      {:error, Error.new(:unauthorized, "invalid credentials")}
    end
  end

  defp ensure_not_banned(%{banned_at: nil}), do: :ok

  defp ensure_not_banned(_) do
    {:error, Error.new(:unauthorized, "device_banned")}
  end

  defp issue_token(fields) do
    plain = Token.generate()
    ttl = Application.get_env(:im, :token_ttl_sec, 86_400)
    expires_at = DateTime.utc_now() |> DateTime.add(ttl, :second) |> DateTime.truncate(:microsecond)

    case AccessTokenStore.insert(%{
           app_key: fields.app_key,
           user_id: fields.user_id,
           device_id: fields.device_id,
           token_hash: Token.hash(plain),
           expires_at: expires_at
         }) do
      {:ok, _} -> {:ok, plain, expires_at}
      {:error, _} = err -> err
    end
  end

  defp websocket_urls do
    Application.get_env(:im, :websocket_urls, ["ws://localhost:4000/ws"])
  end

  defp connection_config do
    %{
      heartbeat_interval_sec: Application.get_env(:im, :heartbeat_interval_sec, 30),
      push_batch_max: Application.get_env(:im, :push_batch_max, 50),
      recall_window_sec: Application.get_env(:im, :recall_window_sec, 120),
      edit_window_sec: Application.get_env(:im, :edit_window_sec, 86_400),
      offline_pull_limit: Application.get_env(:im, :offline_pull_limit, 200),
      payload_compression: "none",
      burn_after_read_enabled: Application.get_env(:im, :burn_after_read_enabled, false),
      burn_ttl_sec_default: Application.get_env(:im, :burn_ttl_sec_default, 30),
      burn_ttl_sec_max: Application.get_env(:im, :burn_ttl_sec_max, 300)
    }
  end
end
