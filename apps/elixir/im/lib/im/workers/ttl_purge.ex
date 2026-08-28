defmodule IM.Workers.TtlPurge do
  @moduledoc "消息 TTL 清理 Oban Worker（P7-10）。"

  use Oban.Worker, queue: :ttl_purge, max_attempts: 3

  alias IM.Jobs.TtlPurge

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    opts =
      []
      |> maybe_put(:app_key, args["app_key"])
      |> maybe_put(:msg_ttl_days, args["msg_ttl_days"])
      |> maybe_put(:batch, args["batch"])

    _ = TtlPurge.purge(opts)
    :ok
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
