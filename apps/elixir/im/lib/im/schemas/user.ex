defmodule IM.Schemas.User do
  @moduledoc """
  租户用户。MVP 在表内存 `password_hash`（SHA-256），后续可换外部用户源。
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  schema "users" do
    field :app_key, :string
    field :user_id, :string
    field :nickname, :string
    field :avatar_url, :string
    field :password_hash, :string
    field :muted, :boolean, default: false
    field :disabled_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [
      :app_key,
      :user_id,
      :nickname,
      :avatar_url,
      :password_hash,
      :muted,
      :disabled_at
    ])
    |> validate_required([:app_key, :user_id])
    |> unique_constraint([:app_key, :user_id])
  end
end
