defmodule IM.Schemas.RoomMember do
  @moduledoc "聊天室成员。"
  use Ecto.Schema

  import Ecto.Changeset

  schema "room_members" do
    field :app_key, :string
    field :room_id, :string
    field :user_id, :string
    field :joined_at, :utc_datetime_usec
  end

  def changeset(member, attrs) do
    member
    |> cast(attrs, [:app_key, :room_id, :user_id, :joined_at])
    |> validate_required([:app_key, :room_id, :user_id, :joined_at])
    |> unique_constraint([:app_key, :room_id, :user_id])
  end
end
