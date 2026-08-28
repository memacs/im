defmodule Pb.Im.Protocol.DeviceResource do
  @moduledoc false

  use Protobuf,
    full_name: "im.protocol.DeviceResource",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:device_id, 1, type: :string, json_name: "deviceId")
  field(:session_id, 2, type: :string, json_name: "sessionId")
  field(:platform, 3, type: :string)
  field(:os, 4, type: :string)
  field(:sdk_ver, 5, type: :string, json_name: "sdkVer")
  field(:device_name, 6, type: :string, json_name: "deviceName")
  field(:device_model, 7, type: :string, json_name: "deviceModel")
  field(:network, 8, type: :string)
  field(:client_ip, 9, type: :string, json_name: "clientIp")
  field(:connected_at, 10, type: :int64, json_name: "connectedAt")
end

defmodule Pb.Im.Protocol.AuthReq do
  @moduledoc false

  use Protobuf,
    full_name: "im.protocol.AuthReq",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:app_key, 1, type: :string, json_name: "appKey")
  field(:user_id, 2, type: :string, json_name: "userId")
  field(:token, 3, type: :string)
  field(:device_id, 4, type: :string, json_name: "deviceId")
  field(:platform, 5, type: :string)
  field(:sdk_ver, 6, type: :string, json_name: "sdkVer")
  field(:os, 7, type: :string)
  field(:device_name, 8, type: :string, json_name: "deviceName")
  field(:device_model, 9, type: :string, json_name: "deviceModel")
  field(:network, 10, type: :string)

  field(:compression_offered, 11,
    repeated: true,
    type: Pb.Im.Protocol.PayloadCompression,
    json_name: "compressionOffered",
    enum: true
  )
end

defmodule Pb.Im.Protocol.AuthResp do
  @moduledoc false

  use Protobuf,
    full_name: "im.protocol.AuthResp",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:device, 1, type: Pb.Im.Protocol.DeviceResource)
  field(:server_time, 2, type: :int64, json_name: "serverTime")
  field(:heartbeat_interval_sec, 3, type: :int32, json_name: "heartbeatIntervalSec")
  field(:user_id, 4, type: :string, json_name: "userId")
  field(:push_batch_max, 5, type: :int32, json_name: "pushBatchMax")
  field(:recall_window_sec, 6, type: :int32, json_name: "recallWindowSec")
  field(:edit_window_sec, 7, type: :int32, json_name: "editWindowSec")
  field(:offline_pull_limit, 8, type: :int32, json_name: "offlinePullLimit")
  field(:clear_local_data, 9, type: :bool, json_name: "clearLocalData")

  field(:payload_compression, 10,
    type: Pb.Im.Protocol.PayloadCompression,
    json_name: "payloadCompression",
    enum: true
  )

  field(:burn_after_read_enabled, 11, type: :bool, json_name: "burnAfterReadEnabled")
  field(:burn_ttl_sec_default, 12, type: :int32, json_name: "burnTtlSecDefault")
  field(:burn_ttl_sec_max, 13, type: :int32, json_name: "burnTtlSecMax")
end

defmodule Pb.Im.Protocol.HeartbeatReq do
  @moduledoc false

  use Protobuf,
    full_name: "im.protocol.HeartbeatReq",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:client_time, 1, type: :int64, json_name: "clientTime")
end

defmodule Pb.Im.Protocol.HeartbeatResp do
  @moduledoc false

  use Protobuf,
    full_name: "im.protocol.HeartbeatResp",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:server_time, 1, type: :int64, json_name: "serverTime")
end

defmodule Pb.Im.Protocol.KickNotify do
  @moduledoc false

  use Protobuf,
    full_name: "im.protocol.KickNotify",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:reason, 1, type: :string)
  field(:kicker, 2, type: Pb.Im.Protocol.DeviceResource)
  field(:timestamp, 3, type: :int64)
  field(:clear_local_data, 4, type: :bool, json_name: "clearLocalData")
end
