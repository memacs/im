defmodule IM.Schemas.IdWorker do
  @moduledoc "`msg_id` Snowflake worker 租约镜像（PG）。"
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  schema "id_workers" do
    field :worker_id, :integer, primary_key: true
    field :node_name, :string
    field :lease_until, :utc_datetime_usec
    field :updated_at, :utc_datetime_usec
  end

  def changeset(row, attrs) do
    row
    |> cast(attrs, [:worker_id, :node_name, :lease_until, :updated_at])
    |> validate_required([:worker_id, :node_name, :lease_until, :updated_at])
    |> validate_number(:worker_id, greater_than_or_equal_to: 0, less_than_or_equal_to: 1023)
  end
end
