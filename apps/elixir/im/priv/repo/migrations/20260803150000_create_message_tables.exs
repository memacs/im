defmodule IM.Repo.Migrations.CreateMessageTables do
  use Ecto.Migration

  def change do
    create table(:message_bodies, primary_key: false) do
      add :app_key, :string, size: 64, null: false, primary_key: true
      add :msg_id, :string, size: 64, null: false, primary_key: true
      add :chat_type, :smallint, null: false
      add :conv_id, :string, size: 128, null: false
      add :from_uid, :string, size: 64, null: false
      add :to_id, :string, size: 64, null: false
      add :msg_type, :smallint, null: false
      add :content, :binary, null: false
      add :server_time, :bigint, null: false
      add :conv_seq, :bigint, null: false
      add :client_msg_id, :string, size: 64
      add :target_users, {:array, :string}
      add :recalled, :boolean, null: false, default: false
      add :edit_version, :integer, null: false, default: 0
      add :burn_after_read, :boolean, null: false, default: false
      add :burn_ttl_sec, :integer, null: false, default: 0
      add :burned, :boolean, null: false, default: false
      add :burn_at, :utc_datetime_usec
      add :ext, :map

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:message_bodies, [:app_key, :conv_id, :conv_seq],
      name: :idx_message_bodies_conv
    )

    create unique_index(:message_bodies, [:app_key, :from_uid, :client_msg_id],
      where: "client_msg_id IS NOT NULL",
      name: :idx_message_bodies_client_msg
    )

    create table(:user_inbox, primary_key: false) do
      add :app_key, :string, size: 64, null: false, primary_key: true
      add :user_id, :string, size: 64, null: false, primary_key: true
      add :msg_id, :string, size: 64, null: false, primary_key: true
      add :conv_id, :string, size: 128, null: false
      add :inbox_seq, :bigint, null: false
      add :conv_seq, :bigint, null: false
      add :created_at, :utc_datetime_usec, null: false
    end

    create unique_index(:user_inbox, [:app_key, :user_id, :inbox_seq], name: :idx_user_inbox_seq)
    create index(:user_inbox, [:app_key, :user_id, :conv_id, :conv_seq], name: :idx_user_inbox_conv)

    create table(:msg_sequences) do
      add :app_key, :string, size: 64, null: false
      add :seq_type, :string, size: 32, null: false
      add :seq_key, :string, size: 128, null: false
      add :current_val, :bigint, null: false, default: 0
      add :updated_at, :utc_datetime_usec, null: false
    end

    create unique_index(:msg_sequences, [:app_key, :seq_type, :seq_key])

    create table(:id_workers, primary_key: false) do
      add :worker_id, :smallint, primary_key: true
      add :node_name, :string, size: 255, null: false
      add :lease_until, :utc_datetime_usec, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end
  end
end
