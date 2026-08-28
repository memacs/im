defmodule IM.Services.Auth do
  @moduledoc """
  `CMD_AUTH_REQ` 业务：校验 token、设备限制、构造 `AuthResp` 所需数据。
  """

  alias IM.Domain.{Error, MessageContext}
  alias IM.Protocol.Compression
  alias IM.Services.DeviceLimit
  alias IM.Stores.UserDeviceStore
  alias Pb.Im.Protocol.{AuthReq, AuthResp, DeviceResource}

  @doc """
  处理鉴权请求。成功返回 `%{resp: AuthResp.t(), context: MessageContext.t(), kick_oldest: ...}`。

  ## 示例

      IM.Services.Auth.authenticate(%AuthReq{...}, trace_id)
  """
  @spec authenticate(AuthReq.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def authenticate(%AuthReq{} = req, trace_id) when is_binary(trace_id) do
    with {:ok, claims} <- IM.Auth.verify_token(req.token),
         :ok <- ensure_identity_match(req, claims),
         {:ok, device} <-
           UserDeviceStore.upsert(%{
             app_key: claims.app_key,
             user_id: claims.user_id,
             device_id: claims.device_id,
             platform: req.platform || "unknown",
             sdk_ver: req.sdk_ver
           }),
         {:ok, limit_result} <-
           DeviceLimit.enforce(claims.app_key, claims.user_id, claims.device_id, device.platform) do
      session_id = Ecto.UUID.generate()

      ctx =
        MessageContext.from_websocket(%{
          app_key: claims.app_key,
          user_id: claims.user_id,
          device_id: claims.device_id,
          session_id: session_id,
          platform: platform_atom(device.platform),
          trace_id: trace_id,
          node: node(),
          connected_at: DateTime.utc_now()
        })

      chosen = Compression.negotiate(req.compression_offered || [], claims.app_key)

      resp = %AuthResp{
        device: %DeviceResource{
          device_id: claims.device_id,
          session_id: session_id,
          platform: device.platform,
          sdk_ver: req.sdk_ver || "",
          connected_at: DateTime.to_unix(DateTime.utc_now(), :millisecond)
        },
        server_time: System.system_time(:millisecond),
        heartbeat_interval_sec: Application.get_env(:im, :heartbeat_interval_sec, 30),
        user_id: claims.user_id,
        push_batch_max: Application.get_env(:im, :push_batch_max, 50),
        recall_window_sec: Application.get_env(:im, :recall_window_sec, 120),
        edit_window_sec: Application.get_env(:im, :edit_window_sec, 86_400),
        offline_pull_limit: Application.get_env(:im, :offline_pull_limit, 200),
        clear_local_data: device.clear_local_data_pending,
        payload_compression: chosen,
        burn_after_read_enabled: Application.get_env(:im, :burn_after_read_enabled, false),
        burn_ttl_sec_default: Application.get_env(:im, :burn_ttl_sec_default, 30),
        burn_ttl_sec_max: Application.get_env(:im, :burn_ttl_sec_max, 300)
      }

      {:ok,
       %{
         resp: resp,
         context: ctx,
         kick_oldest: limit_result.kick_oldest,
         compression: chosen,
         token_expires_at: claims.expires_at
       }}
    end
  end

  defp ensure_identity_match(%AuthReq{} = req, claims) do
    cond do
      req.user_id != "" and req.user_id != claims.user_id ->
        {:error, Error.new(:unauthorized, "user_id mismatch")}

      req.device_id != "" and req.device_id != claims.device_id ->
        {:error, Error.new(:unauthorized, "device_id mismatch")}

      req.app_key != "" and req.app_key != claims.app_key ->
        {:error, Error.new(:unauthorized, "app_key mismatch")}

      true ->
        :ok
    end
  end

  defp platform_atom(platform) when is_binary(platform) do
    String.to_atom(platform)
  rescue
    _ -> :unknown
  end
end
