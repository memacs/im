defmodule IM.Schemas.Room do
  @moduledoc "聊天室元数据。"
  use Ecto.Schema

  import Ecto.Changeset

  schema "rooms" do
    field(:app_key, :string)
    field(:room_id, :string)
    field(:name, :string)
    field(:owner_uid, :string)
    field(:max_members, :integer, default: 10_000)
    field(:member_count, :integer, default: 0)
    field(:persist_msg, :boolean, default: false)
    field(:msg_ttl_sec, :integer, default: 300)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(room, attrs) do
    room
    |> cast(attrs, [
      :app_key,
      :room_id,
      :name,
      :owner_uid,
      :max_members,
      :member_count,
      :persist_msg,
      :msg_ttl_sec
    ])
    |> validate_required([:app_key, :room_id, :name, :owner_uid])
    |> unique_constraint([:app_key, :room_id])
  end
end
