defmodule IM.Workers.UnreadFlush do
  @moduledoc "未读数 Redis pending → PG 刷库 Worker。"

  use Oban.Worker, queue: :ttl_purge, max_attempts: 3

  alias IM.Jobs.UnreadFlush

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    app_key = Map.get(args, "app_key") || "app_demo"
    batch = Map.get(args, "batch") || 500
    _ = UnreadFlush.run_once(app_key: app_key, batch: batch)
    {:ok, :flushed}
  end
end
