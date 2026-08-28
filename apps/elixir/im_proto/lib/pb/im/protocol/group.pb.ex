defmodule Pb.Im.Protocol.GroupMemberRole do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "im.protocol.GroupMemberRole",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:GROUP_MEMBER_ROLE_UNSPECIFIED, 0)
  field(:GROUP_MEMBER_ROLE_MEMBER, 1)
  field(:GROUP_MEMBER_ROLE_ADMIN, 2)
  field(:GROUP_MEMBER_ROLE_OWNER, 3)
end

defmodule Pb.Im.Protocol.GroupCreateReq.ExtEntry do
  @moduledoc false

  use Protobuf,
    full_name: "im.protocol.GroupCreateReq.ExtEntry",
    map: true,
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Pb.Im.Protocol.GroupCreateReq do
  @moduledoc false

  use Protobuf,
    full_name: "im.protocol.GroupCreateReq",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:group_id, 1, type: :string, json_name: "groupId")
  field(:name, 2, type: :string)
  field(:announcement, 3, type: :string)
  field(:max_members, 4, type: :int32, json_name: "maxMembers")
  field(:member_uids, 5, repeated: true, type: :string, json_name: "memberUids")
  field(:ext, 6, repeated: true, type: Pb.Im.Protocol.GroupCreateReq.ExtEntry, map: true)
end

defmodule Pb.Im.Protocol.GroupCreateResp do
  @moduledoc false

  use Protobuf,
    full_name: "im.protocol.GroupCreateResp",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:group_id, 1, type: :string, json_name: "groupId")
  field(:name, 2, type: :string)
  field(:conv_id, 3, type: :string, json_name: "convId")
  field(:created_at, 4, type: :int64, json_name: "createdAt")
end

defmodule Pb.Im.Protocol.GroupOperateReq do
  @moduledoc false

  use Protobuf,
    full_name: "im.protocol.GroupOperateReq",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:group_id, 1, type: :string, json_name: "groupId")
  field(:reason, 2, type: :string)
end

defmodule Pb.Im.Protocol.GroupOperatePush do
  @moduledoc false

  use Protobuf,
    full_name: "im.protocol.GroupOperatePush",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:group_id, 1, type: :string, json_name: "groupId")
  field(:conv_id, 2, type: :string, json_name: "convId")
  field(:operator_uid, 3, type: :string, json_name: "operatorUid")
  field(:reason, 4, type: :string)
  field(:timestamp, 5, type: :int64)
end

defmodule Pb.Im.Protocol.GroupMemberPush do
  @moduledoc false

  use Protobuf,
    full_name: "im.protocol.GroupMemberPush",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:group_id, 1, type: :string, json_name: "groupId")
  field(:conv_id, 2, type: :string, json_name: "convId")
  field(:operator_uid, 3, type: :string, json_name: "operatorUid")
  field(:member_uids, 4, repeated: true, type: :string, json_name: "memberUids")
  field(:timestamp, 5, type: :int64)
end

defmodule Pb.Im.Protocol.GroupKickReq do
  @moduledoc false

  use Protobuf,
    full_name: "im.protocol.GroupKickReq",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:group_id, 1, type: :string, json_name: "groupId")
  field(:member_uids, 2, repeated: true, type: :string, json_name: "memberUids")
  field(:reason, 3, type: :string)
end

defmodule Pb.Im.Protocol.GroupInviteReq do
  @moduledoc false

  use Protobuf,
    full_name: "im.protocol.GroupInviteReq",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:group_id, 1, type: :string, json_name: "groupId")
  field(:member_uids, 2, repeated: true, type: :string, json_name: "memberUids")
end

defmodule Pb.Im.Protocol.GroupAdminReq do
  @moduledoc false

  use Protobuf,
    full_name: "im.protocol.GroupAdminReq",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:group_id, 1, type: :string, json_name: "groupId")
  field(:member_uid, 2, type: :string, json_name: "memberUid")
end

defmodule Pb.Im.Protocol.GroupAdminPush do
  @moduledoc false

  use Protobuf,
    full_name: "im.protocol.GroupAdminPush",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:group_id, 1, type: :string, json_name: "groupId")
  field(:conv_id, 2, type: :string, json_name: "convId")
  field(:operator_uid, 3, type: :string, json_name: "operatorUid")
  field(:member_uid, 4, type: :string, json_name: "memberUid")
  field(:new_role, 5, type: Pb.Im.Protocol.GroupMemberRole, json_name: "newRole", enum: true)
  field(:timestamp, 6, type: :int64)
end

defmodule Pb.Im.Protocol.GroupTransferReq do
  @moduledoc false

  use Protobuf,
    full_name: "im.protocol.GroupTransferReq",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:group_id, 1, type: :string, json_name: "groupId")
  field(:new_owner_uid, 2, type: :string, json_name: "newOwnerUid")
end

defmodule Pb.Im.Protocol.GroupTransferPush do
  @moduledoc false

  use Protobuf,
    full_name: "im.protocol.GroupTransferPush",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:group_id, 1, type: :string, json_name: "groupId")
  field(:conv_id, 2, type: :string, json_name: "convId")
  field(:old_owner_uid, 3, type: :string, json_name: "oldOwnerUid")
  field(:new_owner_uid, 4, type: :string, json_name: "newOwnerUid")
  field(:timestamp, 5, type: :int64)
end

defmodule Pb.Im.Protocol.GroupUpdateReq.ExtEntry do
  @moduledoc false

  use Protobuf,
    full_name: "im.protocol.GroupUpdateReq.ExtEntry",
    map: true,
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Pb.Im.Protocol.GroupUpdateReq do
  @moduledoc false

  use Protobuf,
    full_name: "im.protocol.GroupUpdateReq",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:group_id, 1, type: :string, json_name: "groupId")
  field(:name, 2, type: :string)
  field(:announcement, 3, type: :string)
  field(:max_members, 4, type: :int32, json_name: "maxMembers")
  field(:ext, 5, repeated: true, type: Pb.Im.Protocol.GroupUpdateReq.ExtEntry, map: true)
end

defmodule Pb.Im.Protocol.GroupUpdatePush do
  @moduledoc false

  use Protobuf,
    full_name: "im.protocol.GroupUpdatePush",
    protoc_gen_elixir_version: "0.17.0",
    syntax: :proto3

  field(:group_id, 1, type: :string, json_name: "groupId")
  field(:conv_id, 2, type: :string, json_name: "convId")
  field(:operator_uid, 3, type: :string, json_name: "operatorUid")
  field(:name, 4, type: :string)
  field(:announcement, 5, type: :string)
  field(:timestamp, 6, type: :int64)
end
