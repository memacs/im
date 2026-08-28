defmodule IM.Connection.Registry do
  @moduledoc """
  本节点连接注册：按 `(app_key, user_id, device_id)` 唯一定位 pid，
  并维护 `(app_key, user_id)` 下的设备列表（duplicate）。
  """

  @doc """
  注册当前进程为设备连接。

  ## 示例

      IM.Connection.Registry.register("a", "u", "d", "ios")
  """
  @spec register(String.t(), String.t(), String.t(), String.t()) :: :ok
  def register(app_key, user_id, device_id, platform) do
    meta = %{device_id: device_id, platform: platform, node: node()}

    _ = register_unique(IM.Connection.DeviceRegistry, {app_key, user_id, device_id}, meta)
    _ = register_dup(IM.Connection.UserRegistry, {app_key, user_id}, meta)
    :ok
  end

  defp register_unique(reg, key, meta) do
    case Registry.register(reg, key, meta) do
      {:ok, _} -> :ok
      {:error, {:already_registered, _}} -> :ok
    end
  end

  defp register_dup(reg, key, meta) do
    case Registry.register(reg, key, meta) do
      {:ok, _} -> :ok
      {:error, {:already_registered, _}} -> :ok
    end
  end

  @doc """
  按设备查找本节点 pid。

  ## 示例

      IM.Connection.Registry.lookup_device("a", "u", "d")
  """
  @spec lookup_device(String.t(), String.t(), String.t()) :: {:ok, pid()} | :error
  def lookup_device(app_key, user_id, device_id) do
    case Registry.lookup(IM.Connection.DeviceRegistry, {app_key, user_id, device_id}) do
      [{pid, _meta}] -> {:ok, pid}
      _ -> :error
    end
  end

  @doc """
  用户在本节点的在线设备元数据列表。

  ## 示例

      IM.Connection.Registry.list_user_devices("a", "u")
  """
  @spec list_user_devices(String.t(), String.t()) :: [map()]
  def list_user_devices(app_key, user_id) do
    Registry.lookup(IM.Connection.UserRegistry, {app_key, user_id})
    |> Enum.map(fn {_pid, meta} -> meta end)
  end

  @doc """
  向设备连接进程投递消息。

  ## 示例

      IM.Connection.Registry.send_device("a", "u", "d", {:kick, notify})
  """
  @spec send_device(String.t(), String.t(), String.t(), term()) :: :ok | :error
  def send_device(app_key, user_id, device_id, message) do
    case lookup_device(app_key, user_id, device_id) do
      {:ok, pid} ->
        send(pid, message)
        :ok

      :error ->
        :error
    end
  end
end
