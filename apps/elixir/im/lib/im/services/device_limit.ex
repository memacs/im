defmodule IM.Services.DeviceLimit do
  @moduledoc """
  按平台限制在线设备数。同 device_id 重连不占新名额。
  """

  alias IM.Connection.Registry
  alias IM.Domain.Error

  @doc """
  在 AUTH 成功前检查设备数。

  返回 `{:ok, %{kick_oldest: nil | {app,user,device}}}` 或 `{:error, %Error{code: :device_limit_exceeded}}`。

  ## 示例

      IM.Services.DeviceLimit.enforce("a", "u", "d", "ios")
  """
  @spec enforce(String.t(), String.t(), String.t(), String.t()) ::
          {:ok, %{kick_oldest: nil | tuple()}} | {:error, Error.t()}
  def enforce(app_key, user_id, device_id, platform) do
    cfg =
      Application.get_env(:im, :device_limit, %{
        max_per_platform: 5,
        policy: :kick_oldest_on_platform
      })

    max = Map.get(cfg, :max_per_platform, 5)
    policy = Map.get(cfg, :policy, :kick_oldest_on_platform)

    online =
      Registry.list_user_devices(app_key, user_id)
      |> Enum.filter(fn meta -> meta[:platform] == platform end)

    same = Enum.any?(online, fn meta -> meta[:device_id] == device_id end)
    count = if same, do: length(online), else: length(online) + 1

    cond do
      count <= max ->
        {:ok, %{kick_oldest: nil}}

      policy == :reject ->
        {:error, Error.new(:device_limit_exceeded, "device limit exceeded")}

      policy == :kick_oldest_on_platform ->
        oldest =
          online
          |> Enum.reject(fn meta -> meta[:device_id] == device_id end)
          |> List.first()

        kick =
          if oldest do
            {app_key, user_id, oldest[:device_id]}
          else
            nil
          end

        {:ok, %{kick_oldest: kick}}

      true ->
        {:ok, %{kick_oldest: nil}}
    end
  end
end
