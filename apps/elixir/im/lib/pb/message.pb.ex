defmodule Pb.Im.Protocol.MsgType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:MSG_TYPE_UNSPECIFIED, 0)
  field(:MSG_TEXT, 1)
  field(:MSG_IMAGE, 2)
  field(:MSG_AUDIO, 3)
  field(:MSG_VIDEO, 4)
  field(:MSG_FILE, 5)
  field(:MSG_LOCATION, 6)
  field(:MSG_CUSTOM, 7)
  field(:MSG_STREAM, 8)
end

defmodule Pb.Im.Protocol.StreamStatus do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:STREAM_STATUS_UNSPECIFIED, 0)
  field(:STREAM_STATUS_START, 1)
  field(:STREAM_STATUS_ONGOING, 2)
  field(:STREAM_STATUS_END, 3)
  field(:STREAM_STATUS_CANCEL, 4)
  field(:STREAM_STATUS_ERROR, 5)
end

defmodule Pb.Im.Protocol.MsgPriority do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:MSG_PRIORITY_NORMAL, 0)
  field(:MSG_PRIORITY_HIGH, 1)
  field(:MSG_PRIORITY_LOW, 2)
end

defmodule Pb.Im.Protocol.AckStatus do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:ACK_STATUS_UNSPECIFIED, 0)
  field(:ACK_SERVER_RECEIVED, 1)
  field(:ACK_CLIENT_RECEIVED, 2)
  field(:ACK_READ, 3)
end

defmodule Pb.Im.Protocol.TextContent do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:text, 1, type: :string)
end

defmodule Pb.Im.Protocol.ImageContent do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:url, 1, type: :string)
  field(:thumbnail_url, 2, type: :string, json_name: "thumbnailUrl")
  field(:file_name, 3, type: :string, json_name: "fileName")
  field(:file_size, 4, type: :int64, json_name: "fileSize")
  field(:width, 5, type: :int32)
  field(:height, 6, type: :int32)
  field(:mime_type, 7, type: :string, json_name: "mimeType")
end

defmodule Pb.Im.Protocol.AudioContent do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:url, 1, type: :string)
  field(:file_name, 2, type: :string, json_name: "fileName")
  field(:file_size, 3, type: :int64, json_name: "fileSize")
  field(:duration_ms, 4, type: :int32, json_name: "durationMs")
  field(:mime_type, 5, type: :string, json_name: "mimeType")
end

defmodule Pb.Im.Protocol.VideoContent do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:url, 1, type: :string)
  field(:thumbnail_url, 2, type: :string, json_name: "thumbnailUrl")
  field(:file_name, 3, type: :string, json_name: "fileName")
  field(:file_size, 4, type: :int64, json_name: "fileSize")
  field(:duration_ms, 5, type: :int32, json_name: "durationMs")
  field(:width, 6, type: :int32)
  field(:height, 7, type: :int32)
  field(:mime_type, 8, type: :string, json_name: "mimeType")
end

defmodule Pb.Im.Protocol.FileContent do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:url, 1, type: :string)
  field(:file_name, 2, type: :string, json_name: "fileName")
  field(:file_size, 3, type: :int64, json_name: "fileSize")
  field(:mime_type, 4, type: :string, json_name: "mimeType")
end

defmodule Pb.Im.Protocol.LocationContent do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:latitude, 1, type: :double)
  field(:longitude, 2, type: :double)
  field(:address, 3, type: :string)
  field(:name, 4, type: :string)
end

defmodule Pb.Im.Protocol.CustomContent do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:custom_type, 1, type: :string, json_name: "customType")
  field(:data, 2, type: :bytes)
end

defmodule Pb.Im.Protocol.StreamContent.MetadataEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Pb.Im.Protocol.StreamContent do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:stream_id, 1, type: :string, json_name: "streamId")
  field(:status, 2, type: Pb.Im.Protocol.StreamStatus, enum: true)
  field(:sequence, 3, type: :int32)
  field(:chunk, 4, type: :string)
  field(:content_type, 5, type: :string, json_name: "contentType")
  field(:metadata, 6, repeated: true, type: Pb.Im.Protocol.StreamContent.MetadataEntry, map: true)
end

defmodule Pb.Im.Protocol.ChatMessage.ExtEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Pb.Im.Protocol.ChatMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:msg_id, 1, type: :string, json_name: "msgId")
  field(:client_msg_id, 2, type: :string, json_name: "clientMsgId")
  field(:chat_type, 3, type: Pb.Im.Protocol.ChatType, json_name: "chatType", enum: true)
  field(:from, 4, type: :string)
  field(:to, 5, type: :string)
  field(:conv_id, 12, type: :string, json_name: "convId")
  field(:target_users, 16, repeated: true, type: :string, json_name: "targetUsers")
  field(:msg_type, 6, type: Pb.Im.Protocol.MsgType, json_name: "msgType", enum: true)
  field(:content, 7, type: :bytes)
  field(:server_time, 8, type: :int64, json_name: "serverTime")
  field(:conv_seq, 9, type: :int64, json_name: "convSeq")
  field(:inbox_seq, 15, type: :int64, json_name: "inboxSeq")
  field(:priority, 11, type: Pb.Im.Protocol.MsgPriority, enum: true)
  field(:recalled, 13, type: :bool)
  field(:edit_version, 14, type: :uint32, json_name: "editVersion")
  field(:burn_after_read, 17, type: :bool, json_name: "burnAfterRead")
  field(:burn_ttl_sec, 18, type: :int32, json_name: "burnTtlSec")
  field(:burned, 19, type: :bool)
  field(:ext, 10, repeated: true, type: Pb.Im.Protocol.ChatMessage.ExtEntry, map: true)
end

defmodule Pb.Im.Protocol.MsgSendReq do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:message, 1, type: Pb.Im.Protocol.ChatMessage)
end

defmodule Pb.Im.Protocol.MsgPushBatch do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:messages, 1, repeated: true, type: Pb.Im.Protocol.ChatMessage)
end

defmodule Pb.Im.Protocol.MsgAck do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:msg_id, 1, type: :string, json_name: "msgId")
  field(:client_msg_id, 2, type: :string, json_name: "clientMsgId")
  field(:status, 3, type: Pb.Im.Protocol.AckStatus, enum: true)
  field(:conv_seq, 4, type: :int64, json_name: "convSeq")
end

defmodule Pb.Im.Protocol.MsgAckBatchUp do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:acks, 1, repeated: true, type: Pb.Im.Protocol.MsgAck)
end

defmodule Pb.Im.Protocol.MsgAckBatchDown do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:acks, 1, repeated: true, type: Pb.Im.Protocol.MsgAck)
end

defmodule Pb.Im.Protocol.MsgRead do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:chat_type, 1, type: Pb.Im.Protocol.ChatType, json_name: "chatType", enum: true)
  field(:from, 2, type: :string)
  field(:to, 3, type: :string)
  field(:msg_id, 4, type: :string, json_name: "msgId")
  field(:conv_seq, 5, type: :int64, json_name: "convSeq")
  field(:timestamp, 6, type: :int64)
  field(:conv_id, 7, type: :string, json_name: "convId")
end

defmodule Pb.Im.Protocol.MsgRecall do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:msg_id, 1, type: :string, json_name: "msgId")
  field(:chat_type, 2, type: Pb.Im.Protocol.ChatType, json_name: "chatType", enum: true)
  field(:from, 3, type: :string)
  field(:to, 4, type: :string)
  field(:timestamp, 5, type: :int64)
  field(:reason, 6, type: :string)
  field(:conv_id, 7, type: :string, json_name: "convId")
end

defmodule Pb.Im.Protocol.MsgEdit.ExtEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Pb.Im.Protocol.MsgEdit do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:msg_id, 1, type: :string, json_name: "msgId")
  field(:chat_type, 2, type: Pb.Im.Protocol.ChatType, json_name: "chatType", enum: true)
  field(:from, 3, type: :string)
  field(:to, 4, type: :string)
  field(:msg_type, 5, type: Pb.Im.Protocol.MsgType, json_name: "msgType", enum: true)
  field(:content, 6, type: :bytes)
  field(:timestamp, 7, type: :int64)
  field(:edit_version, 8, type: :uint32, json_name: "editVersion")
  field(:ext, 9, repeated: true, type: Pb.Im.Protocol.MsgEdit.ExtEntry, map: true)
  field(:conv_id, 10, type: :string, json_name: "convId")
end

defmodule Pb.Im.Protocol.MsgBurn do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:msg_id, 1, type: :string, json_name: "msgId")
  field(:chat_type, 2, type: Pb.Im.Protocol.ChatType, json_name: "chatType", enum: true)
  field(:from, 3, type: :string)
  field(:to, 4, type: :string)
  field(:timestamp, 5, type: :int64)
  field(:conv_id, 6, type: :string, json_name: "convId")
  field(:burn_ttl_sec, 7, type: :int32, json_name: "burnTtlSec")
end
