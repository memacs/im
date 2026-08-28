defmodule IM.Schemas.AuditLog do
  @moduledoc "鉴权等审计事件（append-only）。"
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  schema "audit_logs" do
    field(:event, :string)
    field(:app_key, :string)
    field(:user_id, :string)
    field(:device_id, :string)
    field(:strategy, :string)
    field(:result, :string)
    field(:reason, :string)
    field(:client_ip, :string)
    field(:user_agent, :string)
    field(:created_at, :utc_datetime_usec)
  end

  @doc false
  def changeset(log, attrs) do
    log
    |> cast(attrs, [
      :event,
      :app_key,
      :user_id,
      :device_id,
      :strategy,
      :result,
      :reason,
      :client_ip,
      :user_agent,
      :created_at
    ])
    |> validate_required([:event, :result, :created_at])
  end
end
