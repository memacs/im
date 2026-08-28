defmodule IM.Workers.GroupInboxFanout do
  @moduledoc "群 inbox 写扩散 Oban Worker（P5-11）。"

  use Oban.Worker, queue: :inbox_fanout, max_attempts: 5

  alias IM.Jobs.GroupInboxFanout

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    body_attrs = args |> Map.get("body_attrs", %{}) |> take_body_attrs()
    recipients = Map.get(args, "recipient_user_ids") || []

    case GroupInboxFanout.run(body_attrs, recipients) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp take_body_attrs(map) when is_map(map) do
    %{
      app_key: Map.get(map, "app_key") || Map.get(map, :app_key),
      conv_id: Map.get(map, "conv_id") || Map.get(map, :conv_id),
      msg_id: Map.get(map, "msg_id") || Map.get(map, :msg_id),
      conv_seq: Map.get(map, "conv_seq") || Map.get(map, :conv_seq)
    }
  end
end
