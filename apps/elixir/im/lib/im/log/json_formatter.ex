defmodule IM.Log.JsonFormatter do
  @moduledoc """
  生产 NDJSON formatter（DD-028 §2.6.0）。

  不依赖 `logger_json`；挂到 `:logger` `:default_handler`。
  """

  alias IM.Telemetry.Tags

  @service "im"

  @metadata_keys [
    :event,
    :trace_id,
    :app_key,
    :user_id,
    :device_id,
    :session_id,
    :cmd,
    :seq,
    :cid,
    :code,
    :ref_cmd,
    :reason,
    :msg_id,
    :client_msg_id,
    :duration_ms,
    :operation,
    :remote_ip,
    :caller_service,
    :channel_id,
    :namespace,
    :caller_module,
    :caller_file,
    :caller_line
  ]

  @doc """
  Erlang `:logger` formatter 回调。

  ## 示例

      IM.Log.JsonFormatter.format(event, %{})
  """
  @spec format(map(), term()) :: iodata()
  def format(%{level: level, msg: msg, meta: meta} = _event, _opts) do
    event_atom = meta_get(meta, :event)
    event_str = event_name(event_atom, msg)

    base = %{
      "@timestamp" => timestamp(meta),
      "level" => level_string(level),
      "event" => event_str,
      "message" => event_str,
      "service" => @service,
      "host" => Tags.host(),
      "node" => Tags.node_name()
    }

    payload =
      Enum.reduce(@metadata_keys, %{}, fn key, acc ->
        if key == :event do
          acc
        else
          case meta_get(meta, key) do
            nil -> acc
            value -> Map.put(acc, Atom.to_string(key), stringify(value))
          end
        end
      end)

    [Jason.encode_to_iodata!(Map.merge(base, payload)), ?\n]
  end

  def format(_event, _opts), do: []

  defp meta_get(meta, key) when is_map(meta), do: Map.get(meta, key)
  defp meta_get(meta, key) when is_list(meta), do: Keyword.get(meta, key)
  defp meta_get(_, _), do: nil

  defp event_name(event, _msg) when is_atom(event), do: Atom.to_string(event)

  defp event_name(_event, {:string, iodata}) do
    iodata |> IO.chardata_to_string() |> String.trim()
  end

  defp event_name(_event, msg) when is_binary(msg), do: msg
  defp event_name(_, _), do: "log"

  defp timestamp(meta) do
    case meta_get(meta, :time) do
      us when is_integer(us) and us > 1_000_000_000_000 ->
        # 微秒或纳秒：>= ~2001-09 in microseconds
        unit = if us > 1_000_000_000_000_000, do: :nanosecond, else: :microsecond
        us |> DateTime.from_unix!(unit) |> DateTime.to_iso8601()

      {{y, mo, d}, {h, mi, s, μs}} ->
        frac =
          μs
          |> rem(1_000_000)
          |> Integer.to_string()
          |> String.pad_leading(6, "0")
          |> String.slice(0, 3)

        :io_lib.format("~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0B.~tsZ", [
          y,
          mo,
          d,
          h,
          mi,
          s,
          frac
        ])
        |> IO.iodata_to_binary()

      _ ->
        DateTime.utc_now() |> DateTime.to_iso8601()
    end
  rescue
    _ -> DateTime.utc_now() |> DateTime.to_iso8601()
  end

  defp stringify(v) when is_atom(v), do: Atom.to_string(v)
  defp stringify(v) when is_binary(v), do: v
  defp stringify(v) when is_integer(v), do: v
  defp stringify(v) when is_float(v), do: v
  defp stringify(v) when is_boolean(v), do: v
  defp stringify(%DateTime{} = v), do: DateTime.to_iso8601(v)
  defp stringify(v), do: inspect(v)

  defp level_string(level) when is_atom(level), do: Atom.to_string(level)
  defp level_string(level), do: inspect(level)
end
