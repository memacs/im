defmodule IM.Schemas.Group do
  @moduledoc "群元数据。"
  use Ecto.Schema

  import Ecto.Changeset

  schema "groups" do
    field :app_key, :string
    field :group_id, :string
    field :name, :string
    field :owner_uid, :string
    field :announcement, :string
    field :max_members, :integer, default: 5000
    field :member_count, :integer, default: 0
    field :persist_msg, :boolean, default: true
    field :storage_mode, :string, default: "write_fanout"
    field :storage_mode_override, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(group, attrs) do
    group
    |> cast(attrs, [
      :app_key,
      :group_id,
      :name,
      :owner_uid,
      :announcement,
      :max_members,
      :member_count,
      :persist_msg,
      :storage_mode,
      :storage_mode_override
    ])
    |> validate_required([:app_key, :group_id, :name, :owner_uid])
    |> unique_constraint([:app_key, :group_id])
  end
end
