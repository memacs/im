defmodule Pb.Im.Protocol.FriendStatus do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:FRIEND_STATUS_UNSPECIFIED, 0)
  field(:FRIEND_STATUS_NONE, 1)
  field(:FRIEND_STATUS_PENDING, 2)
  field(:FRIEND_STATUS_ACCEPTED, 3)
  field(:FRIEND_STATUS_BLOCKED, 4)
  field(:FRIEND_STATUS_DELETED, 5)
end

defmodule Pb.Im.Protocol.FriendRequestStatus do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:FRIEND_REQUEST_STATUS_UNSPECIFIED, 0)
  field(:FRIEND_REQUEST_STATUS_PENDING, 1)
  field(:FRIEND_REQUEST_STATUS_ACCEPTED, 2)
  field(:FRIEND_REQUEST_STATUS_REJECTED, 3)
  field(:FRIEND_REQUEST_STATUS_EXPIRED, 4)
end

defmodule Pb.Im.Protocol.FriendAddReq do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:to_user_id, 1, type: :string, json_name: "toUserId")
  field(:message, 2, type: :string)
  field(:remark, 3, type: :string)
end

defmodule Pb.Im.Protocol.FriendAddResp do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:request_id, 1, type: :string, json_name: "requestId")
  field(:status, 2, type: Pb.Im.Protocol.FriendStatus, enum: true)
end

defmodule Pb.Im.Protocol.FriendRequestNotify do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:request_id, 1, type: :string, json_name: "requestId")
  field(:from_user_id, 2, type: :string, json_name: "fromUserId")
  field(:from_nickname, 3, type: :string, json_name: "fromNickname")
  field(:from_avatar, 4, type: :string, json_name: "fromAvatar")
  field(:message, 5, type: :string)
  field(:timestamp, 6, type: :int64)
end

defmodule Pb.Im.Protocol.FriendAcceptReq do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:request_id, 1, type: :string, json_name: "requestId")
  field(:from_user_id, 2, type: :string, json_name: "fromUserId")
  field(:remark, 3, type: :string)
end

defmodule Pb.Im.Protocol.FriendAcceptResp do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:friend_user_id, 1, type: :string, json_name: "friendUserId")
  field(:status, 2, type: Pb.Im.Protocol.FriendStatus, enum: true)
end

defmodule Pb.Im.Protocol.FriendAcceptNotify do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:user_id, 1, type: :string, json_name: "userId")
  field(:nickname, 2, type: :string)
  field(:avatar, 3, type: :string)
  field(:remark, 4, type: :string)
  field(:timestamp, 5, type: :int64)
end

defmodule Pb.Im.Protocol.FriendRejectReq do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:request_id, 1, type: :string, json_name: "requestId")
  field(:from_user_id, 2, type: :string, json_name: "fromUserId")
end

defmodule Pb.Im.Protocol.FriendRejectResp do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:friend_user_id, 1, type: :string, json_name: "friendUserId")
end

defmodule Pb.Im.Protocol.FriendRejectNotify do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:user_id, 1, type: :string, json_name: "userId")
  field(:nickname, 2, type: :string)
  field(:timestamp, 3, type: :int64)
end

defmodule Pb.Im.Protocol.FriendDeleteReq do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:friend_user_id, 1, type: :string, json_name: "friendUserId")
end

defmodule Pb.Im.Protocol.FriendDeleteResp do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:friend_user_id, 1, type: :string, json_name: "friendUserId")
end

defmodule Pb.Im.Protocol.FriendDeleteNotify do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:user_id, 1, type: :string, json_name: "userId")
  field(:timestamp, 2, type: :int64)
end

defmodule Pb.Im.Protocol.FriendBlockReq do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:user_id, 1, type: :string, json_name: "userId")
end

defmodule Pb.Im.Protocol.FriendBlockResp do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:user_id, 1, type: :string, json_name: "userId")
end

defmodule Pb.Im.Protocol.FriendBlockNotify do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:user_id, 1, type: :string, json_name: "userId")
  field(:timestamp, 2, type: :int64)
end

defmodule Pb.Im.Protocol.FriendUnblockReq do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:user_id, 1, type: :string, json_name: "userId")
end

defmodule Pb.Im.Protocol.FriendUnblockResp do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:user_id, 1, type: :string, json_name: "userId")
end

defmodule Pb.Im.Protocol.FriendSetRemarkReq do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:friend_user_id, 1, type: :string, json_name: "friendUserId")
  field(:remark, 2, type: :string)
end

defmodule Pb.Im.Protocol.FriendSetRemarkResp do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:friend_user_id, 1, type: :string, json_name: "friendUserId")
  field(:remark, 2, type: :string)
end

defmodule Pb.Im.Protocol.FriendListReq do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:limit, 1, type: :int32)
  field(:cursor, 2, type: :string)
end

defmodule Pb.Im.Protocol.FriendListResp do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:friends, 1, repeated: true, type: Pb.Im.Protocol.FriendInfo)
  field(:next_cursor, 2, type: :string, json_name: "nextCursor")
  field(:has_more, 3, type: :bool, json_name: "hasMore")
end

defmodule Pb.Im.Protocol.FriendInfo do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:user_id, 1, type: :string, json_name: "userId")
  field(:nickname, 2, type: :string)
  field(:avatar, 3, type: :string)
  field(:remark, 4, type: :string)
  field(:status, 5, type: Pb.Im.Protocol.FriendStatus, enum: true)
  field(:created_at, 6, type: :int64, json_name: "createdAt")
  field(:ext, 7, type: :string)
end

defmodule Pb.Im.Protocol.FriendRequestListReq do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:limit, 1, type: :int32)
  field(:cursor, 2, type: :string)
end

defmodule Pb.Im.Protocol.FriendRequestListResp do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:requests, 1, repeated: true, type: Pb.Im.Protocol.FriendRequestInfo)
  field(:next_cursor, 2, type: :string, json_name: "nextCursor")
  field(:has_more, 3, type: :bool, json_name: "hasMore")
end

defmodule Pb.Im.Protocol.FriendRequestInfo do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field(:request_id, 1, type: :string, json_name: "requestId")
  field(:from_user_id, 2, type: :string, json_name: "fromUserId")
  field(:from_nickname, 3, type: :string, json_name: "fromNickname")
  field(:from_avatar, 4, type: :string, json_name: "fromAvatar")
  field(:to_user_id, 5, type: :string, json_name: "toUserId")
  field(:to_nickname, 6, type: :string, json_name: "toNickname")
  field(:to_avatar, 7, type: :string, json_name: "toAvatar")
  field(:message, 8, type: :string)
  field(:status, 9, type: Pb.Im.Protocol.FriendRequestStatus, enum: true)
  field(:timestamp, 10, type: :int64)
end
