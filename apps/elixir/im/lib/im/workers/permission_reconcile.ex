defmodule IM.Workers.PermissionReconcile do
  @moduledoc "权限缓存对账 Oban Worker。"

  use Oban.Worker, queue: :ttl_purge, max_attempts: 3

  alias IM.Permission.Reconciler

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    app_key = Map.get(args, "app_key") || "app_demo"
    sample = Map.get(args, "sample") || 200
    _ = Reconciler.run(app_key, sample: sample)
    :ok
  end
end
