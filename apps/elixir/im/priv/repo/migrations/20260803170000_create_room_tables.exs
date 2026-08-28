defmodule IM.Repo.Migrations.CreateRoomTables do
  use Ecto.Migration

  def change do
    create table(:rooms) do
      add :app_key, :string, size: 64, null: false
      add :room_id, :string, size: 64, null: false
      add :name, :string, size: 256, null: false
      add :owner_uid, :string, size: 64, null: false
      add :max_members, :integer, null: false, default: 10_000
      add :member_count, :integer, null: false, default: 0
      add :persist_msg, :boolean, null: false, default: false
      add :msg_ttl_sec, :integer, null: false, default: 300

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:rooms, [:app_key, :room_id])
    create index(:rooms, [:app_key, :owner_uid], name: :idx_rooms_owner)

    create table(:room_members) do
      add :app_key, :string, size: 64, null: false
      add :room_id, :string, size: 64, null: false
      add :user_id, :string, size: 64, null: false
      add :joined_at, :utc_datetime_usec, null: false
    end

    create unique_index(:room_members, [:app_key, :room_id, :user_id])
    create index(:room_members, [:app_key, :user_id], name: :idx_room_members_user)
  end
end
