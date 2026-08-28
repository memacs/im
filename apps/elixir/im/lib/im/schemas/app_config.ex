defmodule IM.Schemas.AppConfig do
  @moduledoc "租户可扩展配置（`app_configs`）。"
  use Ecto.Schema

  import Ecto.Changeset

  schema "app_configs" do
    field :app_key, :string
    field :category, :string
    field :config_key, :string
    field :config_value, :string
    field :value_type, :string, default: "string"
    field :description, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(row, attrs) do
    row
    |> cast(attrs, [
      :app_key,
      :category,
      :config_key,
      :config_value,
      :value_type,
      :description
    ])
    |> validate_required([:app_key, :category, :config_key, :config_value, :value_type])
    |> unique_constraint([:app_key, :category, :config_key])
  end
end
