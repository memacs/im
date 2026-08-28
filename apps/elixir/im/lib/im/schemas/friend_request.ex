defmodule IM.Schemas.FriendRequest do
  @moduledoc "好友请求。"
  use Ecto.Schema

  import Ecto.Changeset

  schema "friend_requests" do
    field :app_key, :string
    field :request_id, :string
    field :from_user_id, :string
    field :to_user_id, :string
    field :message, :string
    field :status, :string
    field :expires_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(row, attrs) do
    row
    |> cast(attrs, [
      :app_key,
      :request_id,
      :from_user_id,
      :to_user_id,
      :message,
      :status,
      :expires_at
    ])
    |> validate_required([
      :app_key,
      :request_id,
      :from_user_id,
      :to_user_id,
      :status,
      :expires_at
    ])
    |> validate_inclusion(:status, ~w(pending accepted rejected expired))
    |> unique_constraint(:request_id)
  end
end
