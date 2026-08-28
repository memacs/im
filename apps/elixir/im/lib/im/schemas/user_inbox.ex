defmodule IM.Schemas.UserInbox do
  @moduledoc "收件箱瘦行。"
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  schema "user_inbox" do
    field(:app_key, :string, primary_key: true)
    field(:user_id, :string, primary_key: true)
    field(:msg_id, :string, primary_key: true)
    field(:conv_id, :string)
    field(:inbox_seq, :integer)
    field(:conv_seq, :integer)
    field(:created_at, :utc_datetime_usec)
  end

  def changeset(row, attrs) do
    row
    |> cast(attrs, [:app_key, :user_id, :msg_id, :conv_id, :inbox_seq, :conv_seq, :created_at])
    |> validate_required([
      :app_key,
      :user_id,
      :msg_id,
      :conv_id,
      :inbox_seq,
      :conv_seq,
      :created_at
    ])
  end
end
