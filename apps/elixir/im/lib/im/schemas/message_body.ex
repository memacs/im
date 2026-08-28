defmodule IM.Schemas.MessageBody do
  @moduledoc "消息正文（单聊/群聊共用）。"
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  schema "message_bodies" do
    field :app_key, :string, primary_key: true
    field :msg_id, :string, primary_key: true
    field :chat_type, :integer
    field :conv_id, :string
    field :from_uid, :string
    field :to_id, :string
    field :msg_type, :integer
    field :content, :binary
    field :server_time, :integer
    field :conv_seq, :integer
    field :client_msg_id, :string
    field :target_users, {:array, :string}
    field :recalled, :boolean, default: false
    field :edit_version, :integer, default: 0
    field :burn_after_read, :boolean, default: false
    field :burn_ttl_sec, :integer, default: 0
    field :burned, :boolean, default: false
    field :burn_at, :utc_datetime_usec
    field :ext, :map

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(body, attrs) do
    body
    |> cast(attrs, [
      :app_key,
      :msg_id,
      :chat_type,
      :conv_id,
      :from_uid,
      :to_id,
      :msg_type,
      :content,
      :server_time,
      :conv_seq,
      :client_msg_id,
      :target_users,
      :recalled,
      :edit_version,
      :burn_after_read,
      :burn_ttl_sec,
      :burned,
      :burn_at,
      :ext
    ])
    |> validate_required([
      :app_key,
      :msg_id,
      :chat_type,
      :conv_id,
      :from_uid,
      :to_id,
      :msg_type,
      :server_time,
      :conv_seq
    ])
    |> maybe_require_content()
  end

  # 阅后即焚墓碑允许清空 content；Ecto 将 <<>> 视为 blank
  defp maybe_require_content(cs) do
    if get_field(cs, :burned) == true do
      cs
    else
      validate_required(cs, [:content])
    end
  end
end
