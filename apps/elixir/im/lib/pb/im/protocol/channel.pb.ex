defmodule Pb.Im.Protocol.ChannelSubscribeReq do
  @moduledoc false

  use Protobuf,
    full_name: "im.protocol.ChannelSubscribeReq",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:channel_ids, 1, repeated: true, type: :string, json_name: "channelIds")
end

defmodule Pb.Im.Protocol.ChannelSubscribeResp do
  @moduledoc false

  use Protobuf,
    full_name: "im.protocol.ChannelSubscribeResp",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:subscribed, 1, repeated: true, type: :string)
  field(:failed, 2, repeated: true, type: Pb.Im.Protocol.ChannelSubscribeError)
end

defmodule Pb.Im.Protocol.ChannelSubscribeError do
  @moduledoc false

  use Protobuf,
    full_name: "im.protocol.ChannelSubscribeError",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:channel_id, 1, type: :string, json_name: "channelId")
  field(:code, 2, type: :int32)
  field(:msg, 3, type: :string)
end

defmodule Pb.Im.Protocol.ChannelUnsubscribeReq do
  @moduledoc false

  use Protobuf,
    full_name: "im.protocol.ChannelUnsubscribeReq",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:channel_ids, 1, repeated: true, type: :string, json_name: "channelIds")
end

defmodule Pb.Im.Protocol.ChannelUnsubscribeResp do
  @moduledoc false

  use Protobuf,
    full_name: "im.protocol.ChannelUnsubscribeResp",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:unsubscribed, 1, repeated: true, type: :string)
end

defmodule Pb.Im.Protocol.ChannelPublish do
  @moduledoc false

  use Protobuf,
    full_name: "im.protocol.ChannelPublish",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:channel_id, 1, type: :string, json_name: "channelId")
  field(:content_type, 2, type: :string, json_name: "contentType")
  field(:payload, 3, type: :bytes)
  field(:client_event_id, 4, type: :string, json_name: "clientEventId")
end

defmodule Pb.Im.Protocol.ChannelPublishAck do
  @moduledoc false

  use Protobuf,
    full_name: "im.protocol.ChannelPublishAck",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:channel_id, 1, type: :string, json_name: "channelId")
  field(:event_id, 2, type: :string, json_name: "eventId")
  field(:accepted, 3, type: :bool)
end

defmodule Pb.Im.Protocol.ChannelPush do
  @moduledoc false

  use Protobuf,
    full_name: "im.protocol.ChannelPush",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:channel_id, 1, type: :string, json_name: "channelId")
  field(:content_type, 2, type: :string, json_name: "contentType")
  field(:payload, 3, type: :bytes)
  field(:event_id, 4, type: :string, json_name: "eventId")
  field(:server_time, 5, type: :int64, json_name: "serverTime")
  field(:caller_service, 6, type: :string, json_name: "callerService")
end
