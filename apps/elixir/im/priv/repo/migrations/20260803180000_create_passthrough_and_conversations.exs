defmodule IM.Repo.Migrations.CreatePassthroughAndConversations do
  use Ecto.Migration

  def change do
    create table(:passthrough_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :app_key, :string, size: 64, null: false
      add :user_id, :string, size: 64, null: false
      add :from_uid, :string, size: 64, null: false
      add :to_id, :string, size: 64, null: false
      add :chat_type, :smallint, null: false
      add :conv_id, :string, size: 128
      add :action, :string, size: 64, null: false
      add :data, :binary, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :created_at, :utc_datetime_usec, null: false
    end

    create index(:passthrough_messages, [:app_key, :user_id, :created_at])
    create index(:passthrough_messages, [:expires_at])

    create table(:conversations) do
      add :app_key, :string, size: 64, null: false
      add :user_id, :string, size: 64, null: false
      add :chat_type, :smallint, null: false
      add :conv_id, :string, size: 128, null: false
      add :peer_id, :string, size: 64
      add :last_msg_id, :string, size: 64
      add :last_msg_time, :bigint
      add :last_msg_seq, :bigint
      add :unread_count, :integer, null: false, default: 0
      add :last_read_conv_seq, :bigint, null: false, default: 0

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:conversations, [:app_key, :user_id, :conv_id])
  end
end
