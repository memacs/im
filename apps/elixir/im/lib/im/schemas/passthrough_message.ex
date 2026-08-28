defmodule IM.Schemas.PassthroughMessage do
  @moduledoc "透传暂存（登录后补推，不进 OFFLINE_PULL）。"
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "passthrough_messages" do
    field :app_key, :string
    field :user_id, :string
    field :from_uid, :string
    field :to_id, :string
    field :chat_type, :integer
    field :conv_id, :string
    field :action, :string
    field :data, :binary
    field :expires_at, :utc_datetime_usec
    field :created_at, :utc_datetime_usec
  end

  def changeset(row, attrs) do
    row
    |> cast(attrs, [
      :app_key,
      :user_id,
      :from_uid,
      :to_id,
      :chat_type,
      :conv_id,
      :action,
      :data,
      :expires_at,
      :created_at
    ])
    |> validate_required([
      :app_key,
      :user_id,
      :from_uid,
      :to_id,
      :chat_type,
      :action,
      :data,
      :expires_at,
      :created_at
    ])
  end
end
