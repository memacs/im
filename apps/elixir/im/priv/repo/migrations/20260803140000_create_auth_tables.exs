defmodule IM.Repo.Migrations.CreateAuthTables do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :app_key, :string, size: 64, null: false
      add :user_id, :string, size: 64, null: false
      add :nickname, :string, size: 256
      add :avatar_url, :string, size: 512
      add :password_hash, :string, size: 128
      add :muted, :boolean, null: false, default: false
      add :disabled_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:app_key, :user_id])

    create table(:user_devices) do
      add :app_key, :string, size: 64, null: false
      add :user_id, :string, size: 64, null: false
      add :device_id, :string, size: 64, null: false
      add :platform, :string, size: 32, null: false
      add :push_token, :string, size: 256
      add :sdk_ver, :string, size: 32
      add :online, :boolean, null: false, default: false
      add :last_active_at, :utc_datetime_usec
      add :banned_at, :utc_datetime_usec
      add :ban_reason, :string, size: 64
      add :clear_local_data_pending, :boolean, null: false, default: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:user_devices, [:app_key, :user_id, :device_id])
    create index(:user_devices, [:app_key, :user_id])

    create table(:access_tokens) do
      add :app_key, :string, size: 64, null: false
      add :user_id, :string, size: 64, null: false
      add :device_id, :string, size: 64, null: false
      add :token_hash, :string, size: 64, null: false
      add :expires_at, :utc_datetime_usec, null: false
      add :revoked_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:access_tokens, [:token_hash])

    create index(:access_tokens, [:app_key, :user_id, :device_id],
      where: "revoked_at IS NULL",
      name: :idx_access_tokens_user_device_active
    )

    create index(:access_tokens, [:expires_at],
      where: "revoked_at IS NULL",
      name: :idx_access_tokens_expires_active
    )
  end
end
