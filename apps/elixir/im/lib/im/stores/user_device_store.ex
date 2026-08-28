defmodule IM.Stores.UserDeviceStore do
  @moduledoc "用户设备读写。"

  import Ecto.Query

  alias IM.Domain.Error
  alias IM.Repo
  alias IM.Schemas.UserDevice

  @doc """
  查找设备。

  ## 示例

      IM.Stores.UserDeviceStore.get("a", "u", "d")
  """
  @spec get(String.t(), String.t(), String.t()) :: {:ok, UserDevice.t()} | {:error, Error.t()}
  def get(app_key, user_id, device_id) do
    case Repo.get_by(UserDevice, app_key: app_key, user_id: user_id, device_id: device_id) do
      nil -> {:error, Error.new(:unauthorized, "device not found")}
      device -> {:ok, device}
    end
  end

  @doc """
  插入或更新设备基础信息。

  ## 示例

      IM.Stores.UserDeviceStore.upsert(%{app_key: "a", user_id: "u", device_id: "d", platform: "ios"})
  """
  @spec upsert(map()) :: {:ok, UserDevice.t()} | {:error, Error.t()}
  def upsert(attrs) when is_map(attrs) do
    %UserDevice{}
    |> UserDevice.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:platform, :sdk_ver, :push_token, :updated_at]},
      conflict_target: [:app_key, :user_id, :device_id],
      returning: true
    )
    |> wrap()
  end

  @doc """
  标记在线/离线。

  ## 示例

      IM.Stores.UserDeviceStore.set_online("a", "u", "d", true)
  """
  @spec set_online(String.t(), String.t(), String.t(), boolean()) ::
          {:ok, UserDevice.t()} | {:error, Error.t()}
  def set_online(app_key, user_id, device_id, online?) do
    with {:ok, device} <- get(app_key, user_id, device_id) do
      device
      |> UserDevice.changeset(%{
        online: online?,
        last_active_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
      })
      |> Repo.update()
      |> wrap()
    end
  end

  @doc """
  封禁设备。

  ## 示例

      IM.Stores.UserDeviceStore.ban("a", "u", "d", "admin")
  """
  @spec ban(String.t(), String.t(), String.t(), String.t()) ::
          {:ok, UserDevice.t()} | {:error, Error.t()}
  def ban(app_key, user_id, device_id, reason) do
    with {:ok, device} <- ensure_row(app_key, user_id, device_id) do
      device
      |> UserDevice.changeset(%{
        banned_at: DateTime.utc_now() |> DateTime.truncate(:microsecond),
        ban_reason: reason,
        online: false
      })
      |> Repo.update()
      |> wrap()
    end
  end

  @doc """
  设置或清除待清本地数据标记。

  ## 示例

      IM.Stores.UserDeviceStore.set_clear_local_data_pending("a", "u", "d", true)
  """
  @spec set_clear_local_data_pending(String.t(), String.t(), String.t(), boolean()) ::
          {:ok, UserDevice.t()} | {:error, Error.t()}
  def set_clear_local_data_pending(app_key, user_id, device_id, pending?) do
    with {:ok, device} <- ensure_row(app_key, user_id, device_id) do
      device
      |> UserDevice.changeset(%{clear_local_data_pending: pending?})
      |> Repo.update()
      |> wrap()
    end
  end

  @doc """
  同用户同平台设备列表。

  ## 示例

      IM.Stores.UserDeviceStore.list_by_platform("a", "u", "ios")
  """
  @spec list_by_platform(String.t(), String.t(), String.t()) :: [UserDevice.t()]
  def list_by_platform(app_key, user_id, platform) do
    from(d in UserDevice,
      where: d.app_key == ^app_key and d.user_id == ^user_id and d.platform == ^platform
    )
    |> Repo.all()
  end

  @doc """
  注册或清除推送 token（空串清除）。

  ## 示例

      IM.Stores.UserDeviceStore.set_push_token("a", "u", "d", "apns-tok")
  """
  @spec set_push_token(String.t(), String.t(), String.t(), String.t()) ::
          {:ok, UserDevice.t()} | {:error, Error.t()}
  def set_push_token(app_key, user_id, device_id, push_token)
      when is_binary(app_key) and is_binary(user_id) and is_binary(device_id) and
             is_binary(push_token) do
    with {:ok, device} <- ensure_row(app_key, user_id, device_id) do
      token = if push_token == "", do: nil, else: push_token

      device
      |> UserDevice.changeset(%{push_token: token})
      |> Repo.update()
      |> wrap()
    end
  end

  @doc """
  用户带 push_token 的离线设备。
  """
  @spec list_with_push_token(String.t(), String.t()) :: [UserDevice.t()]
  def list_with_push_token(app_key, user_id) do
    from(d in UserDevice,
      where:
        d.app_key == ^app_key and d.user_id == ^user_id and not is_nil(d.push_token) and
          d.push_token != "" and d.online == false
    )
    |> Repo.all()
  end

  @doc "用户全部设备。"
  @spec list_all(String.t(), String.t()) :: [UserDevice.t()]
  def list_all(app_key, user_id) do
    from(d in UserDevice, where: d.app_key == ^app_key and d.user_id == ^user_id)
    |> Repo.all()
  end

  defp ensure_row(app_key, user_id, device_id) do
    case get(app_key, user_id, device_id) do
      {:ok, _} = ok ->
        ok

      {:error, _} ->
        upsert(%{
          app_key: app_key,
          user_id: user_id,
          device_id: device_id,
          platform: "unknown"
        })
    end
  end

  defp wrap({:ok, row}), do: {:ok, row}

  defp wrap({:error, %Ecto.Changeset{} = cs}) do
    {:error, Error.new(:internal_error, inspect(cs.errors))}
  end
end
