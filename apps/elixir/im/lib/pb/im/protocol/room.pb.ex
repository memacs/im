defmodule Pb.Im.Protocol.RoomCreateReq.ExtEntry do
  @moduledoc false

  use Protobuf,
    full_name: "im.protocol.RoomCreateReq.ExtEntry",
    map: true,
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Pb.Im.Protocol.RoomCreateReq do
  @moduledoc false

  use Protobuf,
    full_name: "im.protocol.RoomCreateReq",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:room_id, 1, type: :string, json_name: "roomId")
  field(:name, 2, type: :string)
  field(:max_members, 3, type: :int32, json_name: "maxMembers")
  field(:persist_msg, 4, type: :bool, json_name: "persistMsg")
  field(:msg_ttl_sec, 5, type: :int32, json_name: "msgTtlSec")
  field(:ext, 6, repeated: true, type: Pb.Im.Protocol.RoomCreateReq.ExtEntry, map: true)
end

defmodule Pb.Im.Protocol.RoomCreateResp do
  @moduledoc false

  use Protobuf,
    full_name: "im.protocol.RoomCreateResp",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:room_id, 1, type: :string, json_name: "roomId")
  field(:name, 2, type: :string)
  field(:conv_id, 3, type: :string, json_name: "convId")
  field(:created_at, 4, type: :int64, json_name: "createdAt")
end

defmodule Pb.Im.Protocol.RoomOperateReq do
  @moduledoc false

  use Protobuf,
    full_name: "im.protocol.RoomOperateReq",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:room_id, 1, type: :string, json_name: "roomId")
  field(:reason, 2, type: :string)
end

defmodule Pb.Im.Protocol.RoomOperatePush do
  @moduledoc false

  use Protobuf,
    full_name: "im.protocol.RoomOperatePush",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:room_id, 1, type: :string, json_name: "roomId")
  field(:conv_id, 2, type: :string, json_name: "convId")
  field(:operator_uid, 3, type: :string, json_name: "operatorUid")
  field(:reason, 4, type: :string)
  field(:timestamp, 5, type: :int64)
end

defmodule Pb.Im.Protocol.RoomMemberPush do
  @moduledoc false

  use Protobuf,
    full_name: "im.protocol.RoomMemberPush",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:room_id, 1, type: :string, json_name: "roomId")
  field(:conv_id, 2, type: :string, json_name: "convId")
  field(:operator_uid, 3, type: :string, json_name: "operatorUid")
  field(:member_uids, 4, repeated: true, type: :string, json_name: "memberUids")
  field(:timestamp, 5, type: :int64)
end

defmodule Pb.Im.Protocol.RoomKickReq do
  @moduledoc false

  use Protobuf,
    full_name: "im.protocol.RoomKickReq",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:room_id, 1, type: :string, json_name: "roomId")
  field(:member_uids, 2, repeated: true, type: :string, json_name: "memberUids")
  field(:reason, 3, type: :string)
end

defmodule Pb.Im.Protocol.RoomUpdateReq.ExtEntry do
  @moduledoc false

  use Protobuf,
    full_name: "im.protocol.RoomUpdateReq.ExtEntry",
    map: true,
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Pb.Im.Protocol.RoomUpdateReq do
  @moduledoc false

  use Protobuf,
    full_name: "im.protocol.RoomUpdateReq",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:room_id, 1, type: :string, json_name: "roomId")
  field(:name, 2, type: :string)
  field(:max_members, 3, type: :int32, json_name: "maxMembers")
  field(:persist_msg, 4, type: :bool, json_name: "persistMsg")
  field(:msg_ttl_sec, 5, type: :int32, json_name: "msgTtlSec")
  field(:ext, 6, repeated: true, type: Pb.Im.Protocol.RoomUpdateReq.ExtEntry, map: true)
end

defmodule Pb.Im.Protocol.RoomUpdatePush do
  @moduledoc false

  use Protobuf,
    full_name: "im.protocol.RoomUpdatePush",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:room_id, 1, type: :string, json_name: "roomId")
  field(:conv_id, 2, type: :string, json_name: "convId")
  field(:operator_uid, 3, type: :string, json_name: "operatorUid")
  field(:name, 4, type: :string)
  field(:timestamp, 5, type: :int64)
end
