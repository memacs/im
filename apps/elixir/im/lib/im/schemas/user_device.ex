defmodule IM.Schemas.UserDevice do
  @moduledoc "用户设备：在线态、封禁、待清本地数据标记。"
  use Ecto.Schema

  import Ecto.Changeset

  schema "user_devices" do
    field(:app_key, :string)
    field(:user_id, :string)
    field(:device_id, :string)
    field(:platform, :string)
    field(:push_token, :string)
    field(:sdk_ver, :string)
    field(:online, :boolean, default: false)
    field(:last_active_at, :utc_datetime_usec)
    field(:banned_at, :utc_datetime_usec)
    field(:ban_reason, :string)
    field(:clear_local_data_pending, :boolean, default: false)

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(device, attrs) do
    device
    |> cast(attrs, [
      :app_key,
      :user_id,
      :device_id,
      :platform,
      :push_token,
      :sdk_ver,
      :online,
      :last_active_at,
      :banned_at,
      :ban_reason,
      :clear_local_data_pending
    ])
    |> validate_required([:app_key, :user_id, :device_id, :platform])
    |> unique_constraint([:app_key, :user_id, :device_id])
  end
end
