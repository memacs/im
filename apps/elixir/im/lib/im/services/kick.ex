defmodule IM.Services.Kick do
  @moduledoc "踢人：在线下发 CMD_KICK；可选标记 clear_local_data_pending。"

  alias IM.Connection.Registry
  alias IM.Domain.Error
  alias IM.Protocol.Push
  alias IM.Stores.UserDeviceStore
  alias Pb.Im.Protocol.KickNotify

  @doc "踢用户全部设备。"
  @spec kick_user(String.t(), String.t(), keyword()) :: :ok | {:error, Error.t()}
  def kick_user(app_key, user_id, opts \\ []) when is_binary(app_key) and is_binary(user_id) do
    devices = UserDeviceStore.list_all(app_key, user_id)

    Enum.each(devices, fn d ->
      _ = kick_device(app_key, user_id, d.device_id, opts)
    end)

    :ok
  end

  @doc """
  踢指定设备。

  ## Options

  - `:reason` 字符串
  - `:reason_code` `KickReason` 原子
  - `:clear_local_data` boolean

  ## 示例

      IM.Services.Kick.kick_device("a", "u", "d", reason: "admin", reason_code: :KICK_REASON_ADMIN_KICK)
  """
  @spec kick_device(String.t(), String.t(), String.t(), keyword()) :: :ok | {:error, Error.t()}
  def kick_device(app_key, user_id, device_id, opts \\ []) do
    clear? = Keyword.get(opts, :clear_local_data, false)
    reason = Keyword.get(opts, :reason, "kick")
    reason_code = Keyword.get(opts, :reason_code, :KICK_REASON_ADMIN_KICK)

    if clear? do
      _ = UserDeviceStore.set_clear_local_data_pending(app_key, user_id, device_id, true)
    end

    notify = %KickNotify{
      reason: reason,
      reason_code: reason_code,
      clear_local_data: clear?,
      timestamp: System.system_time(:millisecond)
    }

    with {:ok, packet} <- Push.build(:CMD_KICK, notify, trace_id: Keyword.get(opts, :trace_id, "")) do
      case Registry.send_device(app_key, user_id, device_id, {:im_kick, packet}) do
        :ok -> :ok
        :error -> :ok
      end
    end
  end
end
