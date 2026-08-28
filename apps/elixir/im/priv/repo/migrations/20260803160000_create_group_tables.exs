defmodule IM.Repo.Migrations.CreateGroupTables do
  use Ecto.Migration

  def change do
    create table(:groups) do
      add :app_key, :string, size: 64, null: false
      add :group_id, :string, size: 64, null: false
      add :name, :string, size: 256, null: false
      add :owner_uid, :string, size: 64, null: false
      add :announcement, :string, size: 1024
      add :max_members, :integer, null: false, default: 5000
      add :member_count, :integer, null: false, default: 0
      add :persist_msg, :boolean, null: false, default: true
      add :storage_mode, :string, size: 32, null: false, default: "write_fanout"
      add :storage_mode_override, :string, size: 32

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:groups, [:app_key, :group_id])
    create index(:groups, [:app_key, :owner_uid], name: :idx_groups_owner)

    create table(:group_members) do
      add :app_key, :string, size: 64, null: false
      add :group_id, :string, size: 64, null: false
      add :user_id, :string, size: 64, null: false
      add :role, :smallint, null: false, default: 0
      add :muted_until, :bigint, null: false, default: 0
      add :joined_at, :utc_datetime_usec, null: false
    end

    create unique_index(:group_members, [:app_key, :group_id, :user_id])
    create index(:group_members, [:app_key, :user_id], name: :idx_group_members_user)
  end
end
