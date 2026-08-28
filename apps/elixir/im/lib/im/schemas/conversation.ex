defmodule IM.Schemas.Conversation do
  @moduledoc "用户会话（已读位点等）。"
  use Ecto.Schema

  import Ecto.Changeset

  schema "conversations" do
    field :app_key, :string
    field :user_id, :string
    field :chat_type, :integer
    field :conv_id, :string
    field :peer_id, :string
    field :last_msg_id, :string
    field :last_msg_type, :integer
    field :last_msg_preview, :string
    field :last_msg_time, :integer
    field :last_msg_seq, :integer
    field :unread_count, :integer, default: 0
    field :last_read_conv_seq, :integer, default: 0

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(conv, attrs) do
    conv
    |> cast(attrs, [
      :app_key,
      :user_id,
      :chat_type,
      :conv_id,
      :peer_id,
      :last_msg_id,
      :last_msg_type,
      :last_msg_preview,
      :last_msg_time,
      :last_msg_seq,
      :unread_count,
      :last_read_conv_seq
    ])
    |> validate_required([:app_key, :user_id, :chat_type, :conv_id])
    |> unique_constraint([:app_key, :user_id, :conv_id])
  end
end
