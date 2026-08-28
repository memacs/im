defmodule IM.Repo.Migrations.CreateFriendTables do
  use Ecto.Migration

  def change do
    create table(:friendships) do
      add :app_key, :string, size: 64, null: false
      add :user_id, :string, size: 64, null: false
      add :friend_user_id, :string, size: 64, null: false
      add :status, :string, size: 20, null: false
      add :remark, :string, size: 100

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:friendships, [:app_key, :user_id, :friend_user_id])
    create index(:friendships, [:app_key, :user_id], name: :idx_friendships_user)
    create index(:friendships, [:app_key, :friend_user_id], name: :idx_friendships_friend)
    create index(:friendships, [:app_key, :user_id, :status], name: :idx_friendships_status)

    create table(:friend_requests) do
      add :app_key, :string, size: 64, null: false
      add :request_id, :string, size: 64, null: false
      add :from_user_id, :string, size: 64, null: false
      add :to_user_id, :string, size: 64, null: false
      add :message, :string, size: 500
      add :status, :string, size: 20, null: false
      add :expires_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:friend_requests, [:request_id])
    create index(:friend_requests, [:app_key, :to_user_id, :status], name: :idx_friend_requests_to)
    create index(:friend_requests, [:app_key, :from_user_id], name: :idx_friend_requests_from)
  end
end
