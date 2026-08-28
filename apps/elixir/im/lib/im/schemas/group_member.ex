defmodule IM.Schemas.GroupMember do
  @moduledoc "群成员。"
  use Ecto.Schema

  import Ecto.Changeset

  schema "group_members" do
    field(:app_key, :string)
    field(:group_id, :string)
    field(:user_id, :string)
    field(:role, :integer, default: 0)
    field(:muted_until, :integer, default: 0)
    field(:joined_at, :utc_datetime_usec)
  end

  def changeset(member, attrs) do
    member
    |> cast(attrs, [:app_key, :group_id, :user_id, :role, :muted_until, :joined_at])
    |> validate_required([:app_key, :group_id, :user_id, :joined_at])
    |> unique_constraint([:app_key, :group_id, :user_id])
  end
end
