defmodule IM.Jobs.MessageBurn do
  @moduledoc "阅后即焚销毁（P7-09）；经 Oban `IM.Workers.MessageBurn` 调度。"

  alias IM.Delivery.Router
  alias IM.Protocol.Push
  alias IM.Stores.MessageStore
  alias IM.Telemetry.MsgBurn, as: BurnTelemetry
  alias Pb.Im.Protocol.MsgBurn

  @doc """
  调度销毁；ttl_sec=0 近实时执行。
  """
  @spec schedule(String.t(), String.t(), non_neg_integer(), keyword()) :: :ok
  def schedule(app_key, msg_id, ttl_sec, meta \\ []) do
    delay = max(ttl_sec || 0, 0)
    due_at_ms = System.system_time(:millisecond) + delay * 1000

    args = %{
      "app_key" => app_key,
      "msg_id" => msg_id,
      "due_at_ms" => due_at_ms,
      "meta" => meta_to_map(meta)
    }

    opts = if delay > 0, do: [schedule_in: delay], else: []

    case args |> IM.Workers.MessageBurn.new(opts) |> Oban.insert() do
      {:ok, _} ->
        BurnTelemetry.scheduled()
        :ok

      {:error, _} ->
        if delay == 0 do
          BurnTelemetry.scheduled()
          execute(app_key, msg_id, meta, due_at_ms)
        end

        :ok
    end
  end

  @doc false
  def execute(app_key, msg_id, meta, due_at_ms \\ nil) do
    lag_ms = lag_ms(due_at_ms)

    case MessageStore.mark_burned(app_key, msg_id) do
      {:ok, body} ->
        BurnTelemetry.executed(lag_ms)

        burn = %MsgBurn{
          msg_id: body.msg_id,
          chat_type: :CHAT_PRIVATE,
          from: Keyword.get(meta, :from, body.from_uid),
          to: Keyword.get(meta, :to, body.to_id),
          timestamp: System.system_time(:millisecond),
          conv_id: Keyword.get(meta, :conv_id, body.conv_id),
          burn_ttl_sec: body.burn_ttl_sec || 0
        }

        case Push.build(:CMD_MSG_BURN_PUSH, burn, route_key: body.conv_id) do
          {:ok, packet} ->
            _ = Router.push_packet(packet, app_key, body.from_uid)
            _ = Router.push_packet(packet, app_key, body.to_id)
            :ok

          _ ->
            :ok
        end

      _ ->
        :ok
    end
  end

  defp lag_ms(nil), do: 0

  defp lag_ms(due_at_ms) when is_integer(due_at_ms) do
    max(System.system_time(:millisecond) - due_at_ms, 0)
  end

  defp lag_ms(_), do: 0

  defp meta_to_map(meta) when is_list(meta) do
    Map.new(meta, fn {k, v} -> {Atom.to_string(k), v} end)
  end

  defp meta_to_map(meta) when is_map(meta), do: stringify_keys(meta)

  defp stringify_keys(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {to_string(k), v}
    end)
  end
end
