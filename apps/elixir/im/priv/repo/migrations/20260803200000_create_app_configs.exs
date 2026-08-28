defmodule IM.Repo.Migrations.CreateAppConfigs do
  use Ecto.Migration

  def change do
    create table(:app_configs) do
      add :app_key, :string, null: false, size: 64
      add :category, :string, null: false, size: 64
      add :config_key, :string, null: false, size: 128
      add :config_value, :text, null: false
      add :value_type, :string, null: false, default: "string", size: 32
      add :description, :text

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:app_configs, [:app_key, :category, :config_key])
    create index(:app_configs, [:app_key])
    create index(:app_configs, [:app_key, :category])
  end
end
