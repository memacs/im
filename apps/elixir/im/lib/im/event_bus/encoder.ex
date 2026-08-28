defmodule IM.EventBus.Encoder do
  @moduledoc """
  旁路事件序列化。

  默认 `:protobuf`（`Pb.Im.Event.*`）；开发可切 `:json_envelope`。
  """

  alias Pb.Im.Event.{
    AppEvent,
    DownstreamEvent,
    FanoutAudience,
    FanoutInfo,
    PushNotificationBatchEvent,
    PushNotificationTarget,
    SessionEvent,
    UpstreamEvent
  }

  @doc """
  编码为 Kafka value 字节。

  ## 示例

      bin = IM.EventBus.Encoder.encode(:upstream, %{msg_id: "1", app_key: "a"})
  """
  @spec encode(atom(), map()) :: binary()
  def encode(topic, event) when is_atom(topic) and is_map(event) do
    case serialization() do
      :json_envelope -> encode_json(topic, event)
      _ -> encode_pb(topic, event)
    end
  end

  defp serialization do
    conf = Application.get_env(:im, :event_bus_kafka, [])
    Keyword.get(conf, :serialization, :protobuf)
  end

  defp encode_json(topic, event) do
    Jason.encode!(%{
      "topic" => Atom.to_string(topic),
      "ts" => System.system_time(:millisecond),
      "event" => stringify_keys(event)
    })
  end

  defp encode_pb(:upstream, event) do
    %UpstreamEvent{
      event_id: first_str(event, [:event_id, :msg_id]) || Ecto.UUID.generate(),
      timestamp: ts(event),
      app_key: str(event, :app_key),
      trace_id: str(event, :trace_id),
      source: source(event),
      ingress: ingress(event),
      cmd: int(event, :cmd),
      user_id: first_str(event, [:user_id, :from]) || "",
      device_id: str(event, :device_id),
      route_key: str(event, :route_key),
      payload: bytes(event, :payload)
    }
    |> UpstreamEvent.encode()
  end

  defp encode_pb(:session, event) do
    %SessionEvent{
      event_id: first_str(event, [:event_id]) || Ecto.UUID.generate(),
      timestamp: ts(event),
      app_key: str(event, :app_key),
      trace_id: str(event, :trace_id),
      event_type: session_type(event),
      user_id: str(event, :user_id),
      device_id: str(event, :device_id),
      platform: platform_str(event),
      session_id: str(event, :session_id),
      remote_ip: str(event, :remote_ip),
      node: first_str(event, [:node]) || Atom.to_string(Node.self()),
      reason: str(event, :reason)
    }
    |> SessionEvent.encode()
  end

  defp encode_pb(:downstream, event) do
    fanout = Map.get(event, :fanout) || Map.get(event, "fanout") || %{}
    audience = Map.get(fanout, :audience) || Map.get(fanout, "audience") || %{}

    %DownstreamEvent{
      event_id: first_str(event, [:event_id, :msg_id]) || Ecto.UUID.generate(),
      timestamp: ts(event),
      app_key: str(event, :app_key),
      trace_id: str(event, :trace_id),
      cmd: int(event, :cmd),
      chat_type: chat_type(event),
      conv_id: str(event, :conv_id),
      msg_id: str(event, :msg_id),
      fanout: %FanoutInfo{
        mode: fanout_mode(fanout),
        recipient_count: int(fanout, :recipient_count),
        online_count: int(fanout, :online_count),
        audience: %FanoutAudience{
          from_user_id: str(audience, :from_user_id),
          from_device_id: str(audience, :from_device_id),
          recipient_user_ids: list_str(audience, :recipient_user_ids),
          recipient_list_truncated: truthy?(audience, :recipient_list_truncated),
          recipient_list_max: int(audience, :recipient_list_max)
        }
      },
      payload: bytes(event, :payload)
    }
    |> DownstreamEvent.encode()
  end

  defp encode_pb(:push, event) do
    targets =
      (Map.get(event, :targets) || Map.get(event, "targets") || [])
      |> Enum.map(fn t ->
        %PushNotificationTarget{
          user_id: str(t, :user_id),
          device_id: str(t, :device_id),
          platform: platform_str(t),
          push_token: str(t, :push_token)
        }
      end)

    %PushNotificationBatchEvent{
      event_id: first_str(event, [:event_id]) || Ecto.UUID.generate(),
      timestamp: ts(event),
      app_key: str(event, :app_key),
      trace_id: str(event, :trace_id),
      msg_id: str(event, :msg_id),
      conv_id: str(event, :conv_id),
      chat_type: chat_type(event),
      from_user_id: str(event, :from_user_id),
      targets: targets,
      batch_index: int(event, :batch_index),
      batch_total: int(event, :batch_total)
    }
    |> PushNotificationBatchEvent.encode()
  end

  defp encode_pb(:app_events, event) do
    %AppEvent{
      event_id: first_str(event, [:event_id]) || Ecto.UUID.generate(),
      timestamp: ts(event),
      app_key: str(event, :app_key),
      trace_id: str(event, :trace_id),
      channel_id: str(event, :channel_id),
      direction: app_direction(event),
      user_id: str(event, :user_id),
      device_id: str(event, :device_id),
      caller_service: str(event, :caller_service),
      content_type: str(event, :content_type),
      payload: bytes(event, :payload),
      client_event_id: str(event, :client_event_id)
    }
    |> AppEvent.encode()
  end

  defp encode_pb(_other, event), do: encode_json(:dlq, event)

  defp session_type(event) do
    case Map.get(event, :type) || Map.get(event, "type") || Map.get(event, :event_type) do
      "login" -> :SESSION_LOGIN
      "logout" -> :SESSION_LOGOUT
      "heartbeat" -> :SESSION_HEARTBEAT
      :SESSION_LOGIN -> :SESSION_LOGIN
      :SESSION_LOGOUT -> :SESSION_LOGOUT
      :SESSION_HEARTBEAT -> :SESSION_HEARTBEAT
      _ -> :SESSION_EVENT_UNSPECIFIED
    end
  end

  defp fanout_mode(fanout) do
    case Map.get(fanout, :mode) || Map.get(fanout, "mode") do
      :direct -> :FANOUT_DIRECT
      :group_aggregated -> :FANOUT_GROUP_AGGREGATED
      :room_aggregated -> :FANOUT_ROOM_AGGREGATED
      "direct" -> :FANOUT_DIRECT
      "group_aggregated" -> :FANOUT_GROUP_AGGREGATED
      "room_aggregated" -> :FANOUT_ROOM_AGGREGATED
      other when is_atom(other) -> other
      _ -> :FANOUT_UNSPECIFIED
    end
  end

  defp app_direction(event) do
    case Map.get(event, :direction) || Map.get(event, "direction") do
      :APP_EVENT_UP -> :APP_EVENT_UP
      :APP_EVENT_DOWN -> :APP_EVENT_DOWN
      "up" -> :APP_EVENT_UP
      "down" -> :APP_EVENT_DOWN
      _ -> :APP_EVENT_DIRECTION_UNSPECIFIED
    end
  end

  defp chat_type(event) do
    case Map.get(event, :chat_type) || Map.get(event, "chat_type") do
      :CHAT_PRIVATE -> :CHAT_PRIVATE
      :CHAT_GROUP -> :CHAT_GROUP
      :CHAT_ROOM -> :CHAT_ROOM
      "CHAT_PRIVATE" -> :CHAT_PRIVATE
      "CHAT_GROUP" -> :CHAT_GROUP
      "CHAT_ROOM" -> :CHAT_ROOM
      other when is_atom(other) -> other
      _ -> :CHAT_TYPE_UNSPECIFIED
    end
  end

  defp source(event) do
    case Map.get(event, :source) || Map.get(event, "source") do
      :EVENT_SOURCE_WEBSOCKET -> :EVENT_SOURCE_WEBSOCKET
      :EVENT_SOURCE_HTTP -> :EVENT_SOURCE_HTTP
      :EVENT_SOURCE_INTERNAL -> :EVENT_SOURCE_INTERNAL
      "websocket" -> :EVENT_SOURCE_WEBSOCKET
      "http" -> :EVENT_SOURCE_HTTP
      "internal" -> :EVENT_SOURCE_INTERNAL
      _ -> :EVENT_SOURCE_UNSPECIFIED
    end
  end

  defp ingress(event) do
    case Map.get(event, :ingress) || Map.get(event, "ingress") do
      :INGRESS_WS -> :INGRESS_WS
      :INGRESS_REST -> :INGRESS_REST
      :INGRESS_INTERNAL -> :INGRESS_INTERNAL
      "ws" -> :INGRESS_WS
      "http" -> :INGRESS_REST
      "rest" -> :INGRESS_REST
      _ -> :INGRESS_UNSPECIFIED
    end
  end

  defp ts(event) do
    case Map.get(event, :timestamp) || Map.get(event, "timestamp") do
      n when is_integer(n) -> n
      _ -> System.system_time(:millisecond)
    end
  end

  defp first_str(map, keys) when is_map(map) and is_list(keys) do
    Enum.find_value(keys, fn key ->
      case str(map, key) do
        "" -> nil
        v -> v
      end
    end)
  end

  defp str(map, key) when is_map(map) do
    case Map.get(map, key) || Map.get(map, to_string(key)) do
      nil -> ""
      v when is_binary(v) -> v
      v when is_atom(v) -> Atom.to_string(v)
      v -> to_string(v)
    end
  end

  defp int(map, key) when is_map(map) do
    case Map.get(map, key) || Map.get(map, to_string(key)) do
      n when is_integer(n) -> n
      _ -> 0
    end
  end

  defp bytes(map, key) when is_map(map) do
    case Map.get(map, key) || Map.get(map, to_string(key)) do
      bin when is_binary(bin) -> bin
      _ -> <<>>
    end
  end

  defp list_str(map, key) when is_map(map) do
    case Map.get(map, key) || Map.get(map, to_string(key)) do
      list when is_list(list) -> Enum.map(list, &to_string/1)
      _ -> []
    end
  end

  defp truthy?(map, key) do
    Map.get(map, key) || Map.get(map, to_string(key)) || false
  end

  defp platform_str(map) when is_map(map) do
    case Map.get(map, :platform) || Map.get(map, "platform") do
      nil -> ""
      p when is_atom(p) -> Atom.to_string(p)
      p -> to_string(p)
    end
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), stringify_val(v)}
      {k, v} -> {to_string(k), stringify_val(v)}
    end)
  end

  defp stringify_val(%_{} = s), do: s |> Map.from_struct() |> stringify_keys()
  defp stringify_val(list) when is_list(list), do: Enum.map(list, &stringify_val/1)
  defp stringify_val(map) when is_map(map), do: stringify_keys(map)
  defp stringify_val(bin) when is_binary(bin), do: bin
  defp stringify_val(other), do: other
end
