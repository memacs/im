defmodule Pb.Im.Protocol.ProtoVersion do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "im.protocol.ProtoVersion",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:PROTO_VERSION_UNSPECIFIED, 0)
  field(:PROTO_VERSION_V1, 1)
end

defmodule Pb.Im.Protocol.CmdType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "im.protocol.CmdType",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:CMD_UNSPECIFIED, 0)
  field(:CMD_AUTH_REQ, 1)
  field(:CMD_AUTH_RESP, 2)
  field(:CMD_HEARTBEAT_REQ, 3)
  field(:CMD_HEARTBEAT_RESP, 4)
  field(:CMD_KICK, 5)
  field(:CMD_ERROR, 6)
  field(:CMD_MSG_SEND, 100)
  field(:CMD_MSG_PUSH, 101)
  field(:CMD_MSG_PUSH_BATCH, 102)
  field(:CMD_MSG_ACK_UP, 200)
  field(:CMD_MSG_ACK_DOWN, 201)
  field(:CMD_MSG_READ, 202)
  field(:CMD_MSG_ACK_BATCH_UP, 203)
  field(:CMD_MSG_ACK_BATCH_DOWN, 204)
  field(:CMD_OFFLINE_PULL_REQ, 300)
  field(:CMD_OFFLINE_PULL_RESP, 301)
  field(:CMD_MSG_RECALL_REQ, 400)
  field(:CMD_MSG_RECALL_PUSH, 401)
  field(:CMD_MSG_EDIT_REQ, 402)
  field(:CMD_MSG_EDIT_PUSH, 403)
  field(:CMD_MSG_BURN_PUSH, 404)
  field(:CMD_PASSTHROUGH, 500)
  field(:CMD_FRIEND_ADD_REQ, 800)
  field(:CMD_FRIEND_ADD_RESP, 801)
  field(:CMD_FRIEND_REQUEST_PUSH, 802)
  field(:CMD_FRIEND_ACCEPT_REQ, 803)
  field(:CMD_FRIEND_ACCEPT_RESP, 804)
  field(:CMD_FRIEND_ACCEPT_PUSH, 805)
  field(:CMD_FRIEND_REJECT_REQ, 806)
  field(:CMD_FRIEND_REJECT_RESP, 807)
  field(:CMD_FRIEND_REJECT_PUSH, 808)
  field(:CMD_FRIEND_DELETE_REQ, 809)
  field(:CMD_FRIEND_DELETE_RESP, 810)
  field(:CMD_FRIEND_DELETE_PUSH, 811)
  field(:CMD_FRIEND_BLOCK_REQ, 812)
  field(:CMD_FRIEND_BLOCK_RESP, 813)
  field(:CMD_FRIEND_BLOCK_PUSH, 814)
  field(:CMD_FRIEND_UNBLOCK_REQ, 815)
  field(:CMD_FRIEND_UNBLOCK_RESP, 816)
  field(:CMD_FRIEND_SET_REMARK_REQ, 817)
  field(:CMD_FRIEND_SET_REMARK_RESP, 818)
  field(:CMD_FRIEND_LIST_REQ, 819)
  field(:CMD_FRIEND_LIST_RESP, 820)
  field(:CMD_FRIEND_REQUEST_LIST_REQ, 821)
  field(:CMD_FRIEND_REQUEST_LIST_RESP, 822)
  field(:CMD_GROUP_CREATE_REQ, 600)
  field(:CMD_GROUP_CREATE_RESP, 601)
  field(:CMD_GROUP_DISMISS_REQ, 602)
  field(:CMD_GROUP_DISMISS_PUSH, 603)
  field(:CMD_GROUP_JOIN_REQ, 604)
  field(:CMD_GROUP_JOIN_PUSH, 605)
  field(:CMD_GROUP_LEAVE_REQ, 606)
  field(:CMD_GROUP_LEAVE_PUSH, 607)
  field(:CMD_GROUP_KICK_REQ, 608)
  field(:CMD_GROUP_KICK_PUSH, 609)
  field(:CMD_GROUP_INVITE_REQ, 610)
  field(:CMD_GROUP_INVITE_PUSH, 611)
  field(:CMD_GROUP_SET_ADMIN_REQ, 612)
  field(:CMD_GROUP_SET_ADMIN_PUSH, 613)
  field(:CMD_GROUP_REMOVE_ADMIN_REQ, 614)
  field(:CMD_GROUP_REMOVE_ADMIN_PUSH, 615)
  field(:CMD_GROUP_TRANSFER_REQ, 616)
  field(:CMD_GROUP_TRANSFER_PUSH, 617)
  field(:CMD_GROUP_UPDATE_REQ, 618)
  field(:CMD_GROUP_UPDATE_PUSH, 619)
  field(:CMD_ROOM_CREATE_REQ, 700)
  field(:CMD_ROOM_CREATE_RESP, 701)
  field(:CMD_ROOM_DISMISS_REQ, 702)
  field(:CMD_ROOM_DISMISS_PUSH, 703)
  field(:CMD_ROOM_JOIN_REQ, 704)
  field(:CMD_ROOM_JOIN_PUSH, 705)
  field(:CMD_ROOM_LEAVE_REQ, 706)
  field(:CMD_ROOM_LEAVE_PUSH, 707)
  field(:CMD_ROOM_KICK_REQ, 708)
  field(:CMD_ROOM_KICK_PUSH, 709)
  field(:CMD_ROOM_UPDATE_REQ, 710)
  field(:CMD_ROOM_UPDATE_PUSH, 711)
  field(:CMD_CHANNEL_SUBSCRIBE_REQ, 900)
  field(:CMD_CHANNEL_SUBSCRIBE_RESP, 901)
  field(:CMD_CHANNEL_UNSUBSCRIBE_REQ, 902)
  field(:CMD_CHANNEL_UNSUBSCRIBE_RESP, 903)
  field(:CMD_CHANNEL_PUBLISH, 904)
  field(:CMD_CHANNEL_PUBLISH_ACK, 905)
  field(:CMD_CHANNEL_PUSH, 906)
end

defmodule Pb.Im.Protocol.ErrorCode do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "im.protocol.ErrorCode",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:CODE_OK, 0)
  field(:CODE_UNAUTHORIZED, 1001)
  field(:CODE_KICKED, 1002)
  field(:CODE_PROTO_VERSION_UNSUPPORTED, 1003)
  field(:CODE_DEVICE_LIMIT_EXCEEDED, 1004)
  field(:CODE_MSG_INVALID, 2001)
  field(:CODE_MSG_NO_PERMISSION, 2002)
  field(:CODE_MSG_RECALL_DENIED, 2003)
  field(:CODE_CONV_NOT_FOUND, 2004)
  field(:CODE_MSG_EDIT_DENIED, 2005)
  field(:CODE_MSG_BURN_DENIED, 2006)
  field(:CODE_GROUP_NOT_FOUND, 3001)
  field(:CODE_GROUP_NO_PERMISSION, 3002)
  field(:CODE_GROUP_MEMBER_LIMIT, 3003)
  field(:CODE_GROUP_ALREADY_MEMBER, 3004)
  field(:CODE_GROUP_NOT_MEMBER, 3005)
  field(:CODE_ROOM_NOT_FOUND, 4001)
  field(:CODE_ROOM_NO_PERMISSION, 4002)
  field(:CODE_ROOM_MEMBER_LIMIT, 4003)
  field(:CODE_ROOM_ALREADY_MEMBER, 4004)
  field(:CODE_ROOM_NOT_MEMBER, 4005)
  field(:CODE_RATE_LIMITED, 5001)
  field(:CODE_CHANNEL_NOT_FOUND, 6001)
  field(:CODE_CHANNEL_NO_PERMISSION, 6002)
  field(:CODE_CHANNEL_RATE_LIMITED, 6003)
  field(:CODE_FRIEND_SELF, 7001)
  field(:CODE_FRIEND_ALREADY, 7002)
  field(:CODE_FRIEND_BLOCKED, 7003)
  field(:CODE_FRIEND_BLOCKED_BY_PEER, 7004)
  field(:CODE_FRIEND_REQUEST_NOT_FOUND, 7005)
  field(:CODE_FRIEND_NOT_FRIEND, 7006)
  field(:CODE_FRIEND_NO_PERMISSION, 7007)
  field(:CODE_INTERNAL_ERROR, 9000)
end

defmodule Pb.Im.Protocol.ChatType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "im.protocol.ChatType",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:CHAT_TYPE_UNSPECIFIED, 0)
  field(:CHAT_PRIVATE, 1)
  field(:CHAT_GROUP, 2)
  field(:CHAT_ROOM, 3)
end

defmodule Pb.Im.Protocol.PayloadCompression do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "im.protocol.PayloadCompression",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:PAYLOAD_COMPRESSION_UNSPECIFIED, 0)
  field(:PAYLOAD_COMPRESSION_NONE, 1)
  field(:PAYLOAD_COMPRESSION_GZIP, 2)
  field(:PAYLOAD_COMPRESSION_LZ4, 3)
end

defmodule Pb.Im.Protocol.ErrorBody do
  @moduledoc false

  use Protobuf,
    full_name: "im.protocol.ErrorBody",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:code, 1, type: Pb.Im.Protocol.ErrorCode, enum: true)
  field(:msg, 2, type: :string)
  field(:ref_cmd, 3, type: :uint32, json_name: "refCmd")
  field(:ref_cid, 4, type: :string, json_name: "refCid")
end

defmodule Pb.Im.Protocol.Packet do
  @moduledoc false

  use Protobuf,
    full_name: "im.protocol.Packet",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:ver, 1, type: :uint32)
  field(:cmd, 2, type: :uint32)
  field(:seq, 3, type: :uint64)
  field(:ts, 4, type: :int64)
  field(:cid, 5, type: :string)
  field(:trace_id, 6, type: :string, json_name: "traceId")
  field(:payload, 7, type: :bytes)
  field(:route_key, 8, type: :string, json_name: "routeKey")
  field(:compression, 9, type: Pb.Im.Protocol.PayloadCompression, enum: true)
end
