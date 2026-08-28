defmodule IM.Repo.Migrations.CreateAuditLogs do
  use Ecto.Migration

  def change do
    create table(:audit_logs, primary_key: false) do
      add :id, :bigserial, primary_key: true
      add :event, :string, size: 64, null: false
      add :app_key, :string, size: 64
      add :user_id, :string, size: 64
      add :device_id, :string, size: 64
      add :strategy, :string, size: 32
      add :result, :string, size: 16, null: false
      add :reason, :string, size: 256
      add :client_ip, :string, size: 64
      add :user_agent, :string, size: 256
      add :created_at, :utc_datetime_usec, null: false
    end

    create index(:audit_logs, [:app_key, :created_at])
    create index(:audit_logs, [:event, :created_at])
  end
end
