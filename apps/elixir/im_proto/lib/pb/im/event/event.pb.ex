defmodule Pb.Im.Event.EventSource do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "im.event.EventSource",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:EVENT_SOURCE_UNSPECIFIED, 0)
  field(:EVENT_SOURCE_WEBSOCKET, 1)
  field(:EVENT_SOURCE_HTTP, 2)
  field(:EVENT_SOURCE_KAFKA, 3)
  field(:EVENT_SOURCE_INTERNAL, 4)
end

defmodule Pb.Im.Event.IngressType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "im.event.IngressType",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:INGRESS_UNSPECIFIED, 0)
  field(:INGRESS_WS, 1)
  field(:INGRESS_REST, 2)
  field(:INGRESS_INTERNAL, 3)
end

defmodule Pb.Im.Event.SessionEventType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "im.event.SessionEventType",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:SESSION_EVENT_UNSPECIFIED, 0)
  field(:SESSION_LOGIN, 1)
  field(:SESSION_LOGOUT, 2)
  field(:SESSION_HEARTBEAT, 3)
end

defmodule Pb.Im.Event.FanoutMode do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "im.event.FanoutMode",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:FANOUT_UNSPECIFIED, 0)
  field(:FANOUT_DIRECT, 1)
  field(:FANOUT_GROUP_AGGREGATED, 2)
  field(:FANOUT_ROOM_AGGREGATED, 3)
  field(:FANOUT_BATCH, 4)
end

defmodule Pb.Im.Event.PushChannel do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "im.event.PushChannel",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:PUSH_CHANNEL_UNSPECIFIED, 0)
  field(:PUSH_CHANNEL_APNS, 1)
  field(:PUSH_CHANNEL_FCM, 2)
  field(:PUSH_CHANNEL_HMS, 3)
end

defmodule Pb.Im.Event.AppEventDirection do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "im.event.AppEventDirection",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:APP_EVENT_DIRECTION_UNSPECIFIED, 0)
  field(:APP_EVENT_UP, 1)
  field(:APP_EVENT_DOWN, 2)
end

defmodule Pb.Im.Event.UpstreamEvent do
  @moduledoc false

  use Protobuf,
    full_name: "im.event.UpstreamEvent",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:event_id, 1, type: :string, json_name: "eventId")
  field(:timestamp, 2, type: :int64)
  field(:app_key, 3, type: :string, json_name: "appKey")
  field(:trace_id, 4, type: :string, json_name: "traceId")
  field(:source, 5, type: Pb.Im.Event.EventSource, enum: true)
  field(:ingress, 6, type: Pb.Im.Event.IngressType, enum: true)
  field(:cmd, 7, type: :uint32)
  field(:user_id, 8, type: :string, json_name: "userId")
  field(:device_id, 9, type: :string, json_name: "deviceId")
  field(:route_key, 10, type: :string, json_name: "routeKey")
  field(:payload, 11, type: :bytes)
end

defmodule Pb.Im.Event.SessionEvent do
  @moduledoc false

  use Protobuf,
    full_name: "im.event.SessionEvent",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:event_id, 1, type: :string, json_name: "eventId")
  field(:timestamp, 2, type: :int64)
  field(:app_key, 3, type: :string, json_name: "appKey")
  field(:trace_id, 4, type: :string, json_name: "traceId")
  field(:event_type, 5, type: Pb.Im.Event.SessionEventType, json_name: "eventType", enum: true)
  field(:user_id, 6, type: :string, json_name: "userId")
  field(:device_id, 7, type: :string, json_name: "deviceId")
  field(:platform, 8, type: :string)
  field(:session_id, 9, type: :string, json_name: "sessionId")
  field(:remote_ip, 10, type: :string, json_name: "remoteIp")
  field(:node, 11, type: :string)
  field(:reason, 12, type: :string)
end

defmodule Pb.Im.Event.DownstreamEvent do
  @moduledoc false

  use Protobuf,
    full_name: "im.event.DownstreamEvent",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:event_id, 1, type: :string, json_name: "eventId")
  field(:timestamp, 2, type: :int64)
  field(:app_key, 3, type: :string, json_name: "appKey")
  field(:trace_id, 4, type: :string, json_name: "traceId")
  field(:cmd, 5, type: :uint32)
  field(:chat_type, 6, type: Pb.Im.Protocol.ChatType, json_name: "chatType", enum: true)
  field(:conv_id, 7, type: :string, json_name: "convId")
  field(:msg_id, 8, type: :string, json_name: "msgId")
  field(:fanout, 9, type: Pb.Im.Event.FanoutInfo)
  field(:targets, 10, repeated: true, type: Pb.Im.Event.PushTarget)
  field(:payload, 11, type: :bytes)
end

defmodule Pb.Im.Event.FanoutInfo do
  @moduledoc false

  use Protobuf,
    full_name: "im.event.FanoutInfo",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:mode, 1, type: Pb.Im.Event.FanoutMode, enum: true)
  field(:recipient_count, 2, type: :uint32, json_name: "recipientCount")
  field(:online_count, 3, type: :uint32, json_name: "onlineCount")
  field(:target_users, 4, repeated: true, type: :string, json_name: "targetUsers")
  field(:audience, 5, type: Pb.Im.Event.FanoutAudience)
end

defmodule Pb.Im.Event.FanoutAudience do
  @moduledoc false

  use Protobuf,
    full_name: "im.event.FanoutAudience",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:from_user_id, 1, type: :string, json_name: "fromUserId")
  field(:from_device_id, 2, type: :string, json_name: "fromDeviceId")
  field(:recipient_user_ids, 3, repeated: true, type: :string, json_name: "recipientUserIds")
  field(:recipient_list_truncated, 4, type: :bool, json_name: "recipientListTruncated")
  field(:recipient_list_max, 5, type: :uint32, json_name: "recipientListMax")
end

defmodule Pb.Im.Event.PushTarget do
  @moduledoc false

  use Protobuf,
    full_name: "im.event.PushTarget",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:user_id, 1, type: :string, json_name: "userId")
  field(:device_id, 2, type: :string, json_name: "deviceId")
  field(:online, 3, type: :bool)
end

defmodule Pb.Im.Event.PushNotificationBatchEvent do
  @moduledoc false

  use Protobuf,
    full_name: "im.event.PushNotificationBatchEvent",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:event_id, 1, type: :string, json_name: "eventId")
  field(:timestamp, 2, type: :int64)
  field(:app_key, 3, type: :string, json_name: "appKey")
  field(:trace_id, 4, type: :string, json_name: "traceId")
  field(:msg_id, 10, type: :string, json_name: "msgId")
  field(:conv_id, 11, type: :string, json_name: "convId")
  field(:chat_type, 12, type: Pb.Im.Protocol.ChatType, json_name: "chatType", enum: true)
  field(:from_user_id, 13, type: :string, json_name: "fromUserId")
  field(:from_nickname, 14, type: :string, json_name: "fromNickname")
  field(:display, 15, type: Pb.Im.Event.PushDisplay)
  field(:payload, 16, type: :bytes)
  field(:targets, 20, repeated: true, type: Pb.Im.Event.PushNotificationTarget)
  field(:batch_index, 30, type: :uint32, json_name: "batchIndex")
  field(:batch_total, 31, type: :uint32, json_name: "batchTotal")
end

defmodule Pb.Im.Event.PushNotificationTarget do
  @moduledoc false

  use Protobuf,
    full_name: "im.event.PushNotificationTarget",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:user_id, 1, type: :string, json_name: "userId")
  field(:device_id, 2, type: :string, json_name: "deviceId")
  field(:platform, 3, type: :string)
  field(:push_token, 4, type: :string, json_name: "pushToken")
  field(:channel, 5, type: Pb.Im.Event.PushChannel, enum: true)
  field(:idempotency_key, 6, type: :string, json_name: "idempotencyKey")
end

defmodule Pb.Im.Event.PushNotificationEvent do
  @moduledoc false

  use Protobuf,
    deprecated: true,
    full_name: "im.event.PushNotificationEvent",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:event_id, 1, type: :string, json_name: "eventId")
  field(:timestamp, 2, type: :int64)
  field(:app_key, 3, type: :string, json_name: "appKey")
  field(:trace_id, 4, type: :string, json_name: "traceId")
  field(:user_id, 5, type: :string, json_name: "userId")
  field(:device_id, 6, type: :string, json_name: "deviceId")
  field(:platform, 7, type: :string)
  field(:push_token, 8, type: :string, json_name: "pushToken")
  field(:channel, 9, type: Pb.Im.Event.PushChannel, enum: true)
  field(:msg_id, 10, type: :string, json_name: "msgId")
  field(:conv_id, 11, type: :string, json_name: "convId")
  field(:chat_type, 12, type: Pb.Im.Protocol.ChatType, json_name: "chatType", enum: true)
  field(:from_user_id, 13, type: :string, json_name: "fromUserId")
  field(:from_nickname, 14, type: :string, json_name: "fromNickname")
  field(:display, 15, type: Pb.Im.Event.PushDisplay)
  field(:payload, 16, type: :bytes)
  field(:idempotency_key, 17, type: :string, json_name: "idempotencyKey")
end

defmodule Pb.Im.Event.PushDisplay.ExtrasEntry do
  @moduledoc false

  use Protobuf,
    full_name: "im.event.PushDisplay.ExtrasEntry",
    map: true,
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Pb.Im.Event.PushDisplay do
  @moduledoc false

  use Protobuf,
    full_name: "im.event.PushDisplay",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:title, 1, type: :string)
  field(:body, 2, type: :string)
  field(:badge, 3, type: :uint32)
  field(:silent, 4, type: :bool)
  field(:extras, 5, repeated: true, type: Pb.Im.Event.PushDisplay.ExtrasEntry, map: true)
end

defmodule Pb.Im.Event.AppEvent do
  @moduledoc false

  use Protobuf,
    full_name: "im.event.AppEvent",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:event_id, 1, type: :string, json_name: "eventId")
  field(:timestamp, 2, type: :int64)
  field(:app_key, 3, type: :string, json_name: "appKey")
  field(:trace_id, 4, type: :string, json_name: "traceId")
  field(:channel_id, 5, type: :string, json_name: "channelId")
  field(:direction, 6, type: Pb.Im.Event.AppEventDirection, enum: true)
  field(:user_id, 7, type: :string, json_name: "userId")
  field(:device_id, 8, type: :string, json_name: "deviceId")
  field(:caller_service, 9, type: :string, json_name: "callerService")
  field(:content_type, 10, type: :string, json_name: "contentType")
  field(:payload, 11, type: :bytes)
  field(:client_event_id, 12, type: :string, json_name: "clientEventId")
  field(:dropped_before_kafka, 13, type: :uint32, json_name: "droppedBeforeKafka")
end
