defmodule IM.Services.DeviceBan do
  @moduledoc "设备封禁：写 banned_at、吊销 token、在线 KICK。"

  alias IM.Domain.Error
  alias IM.Permission.DeviceBanCache
  alias IM.Services.Kick
  alias IM.Stores.{AccessTokenStore, UserDeviceStore}

  @doc """
  封禁设备。

  ## 示例

      IM.Services.DeviceBan.ban("a", "u", "d", "admin", clear_local_data: true)
  """
  @spec ban(String.t(), String.t(), String.t(), String.t(), keyword()) ::
          :ok | {:error, Error.t()}
  def ban(app_key, user_id, device_id, reason, opts \\ []) do
    clear? = Keyword.get(opts, :clear_local_data, false)

    with {:ok, _} <- UserDeviceStore.ban(app_key, user_id, device_id, reason) do
      :ok = DeviceBanCache.put(app_key, user_id, device_id)
      :ok = AccessTokenStore.revoke_device(app_key, user_id, device_id)

      :ok =
        Kick.kick_device(app_key, user_id, device_id,
          reason: "device_banned",
          reason_code: :KICK_REASON_DEVICE_BANNED,
          clear_local_data: clear?
        )

      :ok
    end
  end

  @doc """
  SDK ACK：清除 `clear_local_data_pending`。

  ## 示例

      IM.Services.DeviceBan.ack_local_data_cleared("a", "u", "d")
  """
  @spec ack_local_data_cleared(String.t(), String.t(), String.t()) ::
          {:ok, term()} | {:error, Error.t()}
  def ack_local_data_cleared(app_key, user_id, device_id) do
    UserDeviceStore.set_clear_local_data_pending(app_key, user_id, device_id, false)
  end
end
