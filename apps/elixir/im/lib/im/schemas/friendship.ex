defmodule IM.Schemas.Friendship do
  @moduledoc "好友关系（含拉黑）。"
  use Ecto.Schema

  import Ecto.Changeset

  schema "friendships" do
    field :app_key, :string
    field :user_id, :string
    field :friend_user_id, :string
    field :status, :string
    field :remark, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(row, attrs) do
    row
    |> cast(attrs, [:app_key, :user_id, :friend_user_id, :status, :remark])
    |> validate_required([:app_key, :user_id, :friend_user_id, :status])
    |> validate_inclusion(:status, ~w(pending accepted blocked deleted))
    |> unique_constraint([:app_key, :user_id, :friend_user_id])
  end
end
