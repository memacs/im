defmodule IM.Schemas.AccessToken do
  @moduledoc "访问令牌：仅存 hash，绑定 app/user/device。"
  use Ecto.Schema

  import Ecto.Changeset

  schema "access_tokens" do
    field :app_key, :string
    field :user_id, :string
    field :device_id, :string
    field :token_hash, :string
    field :expires_at, :utc_datetime_usec
    field :revoked_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(token, attrs) do
    token
    |> cast(attrs, [:app_key, :user_id, :device_id, :token_hash, :expires_at, :revoked_at])
    |> validate_required([:app_key, :user_id, :device_id, :token_hash, :expires_at])
    |> unique_constraint(:token_hash)
  end
end
