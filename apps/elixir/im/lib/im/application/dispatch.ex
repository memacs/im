defmodule IM.Application.Dispatch do
  @moduledoc """
  cmd → Service 的**唯一**映射。WebSocket、REST、Kafka 三条入站路径都必须经此模块。

  设计见 `docs/implementation/elixir/dual-channel-api.md` §2。
  """

  alias IM.Domain.{Error, MessageContext}

  alias IM.Services.{
    Channel,
    DeviceBan,
    Friend,
    Group,
    Heartbeat,
    Message,
    MessageEdit,
    MessageRead,
    MessageRecall,
    Offline,
    Passthrough,
    Room
  }

  alias Pb.Im.Protocol.{
    ChannelPublish,
    ChatMessage,
    CmdType,
    FriendAcceptReq,
    FriendAddReq,
    FriendBlockReq,
    FriendDeleteReq,
    FriendListReq,
    FriendRejectReq,
    FriendRequestListReq,
    FriendSetRemarkReq,
    FriendUnblockReq,
    GroupAdminReq,
    GroupCreateReq,
    GroupInviteReq,
    GroupKickReq,
    GroupOperateReq,
    GroupTransferReq,
    GroupUpdateReq,
    HeartbeatReq,
    MsgAck,
    MsgAckBatchUp,
    MsgEdit,
    MsgRead,
    MsgRecall,
    MsgSendReq,
    OfflinePullReq,
    RoomCreateReq,
    RoomKickReq,
    RoomOperateReq,
    RoomUpdateReq
  }

  alias Pb.Im.Protocol.Passthrough, as: PassthroughBody

  @heartbeat_req CmdType.value(:CMD_HEARTBEAT_REQ)
  @msg_send CmdType.value(:CMD_MSG_SEND)
  @msg_ack_up CmdType.value(:CMD_MSG_ACK_UP)
  @msg_ack_batch_up CmdType.value(:CMD_MSG_ACK_BATCH_UP)
  @msg_read CmdType.value(:CMD_MSG_READ)
  @offline_pull CmdType.value(:CMD_OFFLINE_PULL_REQ)
  @msg_recall CmdType.value(:CMD_MSG_RECALL_REQ)
  @msg_edit CmdType.value(:CMD_MSG_EDIT_REQ)
  @passthrough CmdType.value(:CMD_PASSTHROUGH)

  @group_create CmdType.value(:CMD_GROUP_CREATE_REQ)
  @group_dismiss CmdType.value(:CMD_GROUP_DISMISS_REQ)
  @group_join CmdType.value(:CMD_GROUP_JOIN_REQ)
  @group_leave CmdType.value(:CMD_GROUP_LEAVE_REQ)
  @group_kick CmdType.value(:CMD_GROUP_KICK_REQ)
  @group_invite CmdType.value(:CMD_GROUP_INVITE_REQ)
  @group_set_admin CmdType.value(:CMD_GROUP_SET_ADMIN_REQ)
  @group_remove_admin CmdType.value(:CMD_GROUP_REMOVE_ADMIN_REQ)
  @group_transfer CmdType.value(:CMD_GROUP_TRANSFER_REQ)
  @group_update CmdType.value(:CMD_GROUP_UPDATE_REQ)

  @room_create CmdType.value(:CMD_ROOM_CREATE_REQ)
  @room_dismiss CmdType.value(:CMD_ROOM_DISMISS_REQ)
  @room_join CmdType.value(:CMD_ROOM_JOIN_REQ)
  @room_leave CmdType.value(:CMD_ROOM_LEAVE_REQ)
  @room_kick CmdType.value(:CMD_ROOM_KICK_REQ)
  @room_update CmdType.value(:CMD_ROOM_UPDATE_REQ)

  @friend_add CmdType.value(:CMD_FRIEND_ADD_REQ)
  @friend_accept CmdType.value(:CMD_FRIEND_ACCEPT_REQ)
  @friend_reject CmdType.value(:CMD_FRIEND_REJECT_REQ)
  @friend_delete CmdType.value(:CMD_FRIEND_DELETE_REQ)
  @friend_block CmdType.value(:CMD_FRIEND_BLOCK_REQ)
  @friend_unblock CmdType.value(:CMD_FRIEND_UNBLOCK_REQ)
  @friend_remark CmdType.value(:CMD_FRIEND_SET_REMARK_REQ)
  @friend_list CmdType.value(:CMD_FRIEND_LIST_REQ)
  @friend_request_list CmdType.value(:CMD_FRIEND_REQUEST_LIST_REQ)

  @channel_subscribe CmdType.value(:CMD_CHANNEL_SUBSCRIBE_REQ)
  @channel_unsubscribe CmdType.value(:CMD_CHANNEL_UNSUBSCRIBE_REQ)
  @channel_publish CmdType.value(:CMD_CHANNEL_PUBLISH)

  @doc """
  执行一条命令。

  `cmd` 为 `CmdType` 数值或少量 REST 伪命令原子（如 `:ack_local_data_cleared`）。

  ## 示例

      IM.Application.Dispatch.execute(3, %HeartbeatReq{}, ctx)
  """
  @spec execute(non_neg_integer() | atom(), map() | struct(), MessageContext.t()) ::
          {:ok, term()} | {:error, Error.t()} | :drop_silent
  def execute(@heartbeat_req, %HeartbeatReq{} = payload, %MessageContext{} = ctx) do
    Heartbeat.beat(payload, ctx)
  end

  def execute(@msg_send, %MsgSendReq{message: msg}, %MessageContext{} = ctx)
      when not is_nil(msg) do
    Message.send(msg, ctx)
  end

  def execute(@msg_send, %ChatMessage{} = msg, %MessageContext{} = ctx) do
    Message.send(msg, ctx)
  end

  def execute(@msg_ack_up, %MsgAck{} = ack, %MessageContext{} = ctx) do
    Message.ack_up(ack, ctx)
  end

  def execute(@msg_ack_batch_up, %MsgAckBatchUp{} = batch, %MessageContext{} = ctx) do
    Message.ack_batch_up(batch, ctx)
  end

  def execute(@msg_read, %MsgRead{} = read, %MessageContext{} = ctx) do
    MessageRead.mark(read, ctx)
  end

  def execute(@offline_pull, %OfflinePullReq{} = req, %MessageContext{} = ctx) do
    Offline.pull(req, ctx)
  end

  def execute(@msg_recall, %MsgRecall{} = req, %MessageContext{} = ctx) do
    MessageRecall.recall(req, ctx)
  end

  def execute(@msg_edit, %MsgEdit{} = req, %MessageContext{} = ctx) do
    MessageEdit.edit(req, ctx)
  end

  def execute(@passthrough, %PassthroughBody{} = pt, %MessageContext{} = ctx) do
    Passthrough.send(pt, ctx)
  end

  def execute(@group_create, %GroupCreateReq{} = req, %MessageContext{} = ctx) do
    Group.create(req, ctx)
  end

  def execute(@group_create, params, %MessageContext{} = ctx) when is_map(params) do
    Group.create(params, ctx)
  end

  def execute(@group_dismiss, %GroupOperateReq{} = req, %MessageContext{} = ctx) do
    Group.dismiss(req, ctx)
  end

  def execute(@group_join, %GroupOperateReq{} = req, %MessageContext{} = ctx) do
    Group.join(req, ctx)
  end

  def execute(@group_leave, %GroupOperateReq{} = req, %MessageContext{} = ctx) do
    Group.leave(req, ctx)
  end

  def execute(@group_kick, %GroupKickReq{} = req, %MessageContext{} = ctx) do
    Group.kick(req, ctx)
  end

  def execute(@group_invite, %GroupInviteReq{} = req, %MessageContext{} = ctx) do
    Group.invite(req, ctx)
  end

  def execute(@group_set_admin, %GroupAdminReq{} = req, %MessageContext{} = ctx) do
    Group.set_admin(req, ctx)
  end

  def execute(@group_remove_admin, %GroupAdminReq{} = req, %MessageContext{} = ctx) do
    Group.remove_admin(req, ctx)
  end

  def execute(@group_transfer, %GroupTransferReq{} = req, %MessageContext{} = ctx) do
    Group.transfer(req, ctx)
  end

  def execute(@group_update, %GroupUpdateReq{} = req, %MessageContext{} = ctx) do
    Group.update(req, ctx)
  end

  def execute(@room_create, %RoomCreateReq{} = req, %MessageContext{} = ctx) do
    Room.create(req, ctx)
  end

  def execute(@room_dismiss, %RoomOperateReq{} = req, %MessageContext{} = ctx) do
    Room.dismiss(req, ctx)
  end

  def execute(@room_join, %RoomOperateReq{} = req, %MessageContext{} = ctx) do
    Room.join(req, ctx)
  end

  def execute(@room_leave, %RoomOperateReq{} = req, %MessageContext{} = ctx) do
    Room.leave(req, ctx)
  end

  def execute(@room_kick, %RoomKickReq{} = req, %MessageContext{} = ctx) do
    Room.kick(req, ctx)
  end

  def execute(@room_update, %RoomUpdateReq{} = req, %MessageContext{} = ctx) do
    Room.update(req, ctx)
  end

  def execute(@friend_add, %FriendAddReq{} = req, %MessageContext{} = ctx) do
    Friend.add(req, ctx)
  end

  def execute(@friend_accept, %FriendAcceptReq{} = req, %MessageContext{} = ctx) do
    Friend.accept(req, ctx)
  end

  def execute(@friend_reject, %FriendRejectReq{} = req, %MessageContext{} = ctx) do
    Friend.reject(req, ctx)
  end

  def execute(@friend_delete, %FriendDeleteReq{} = req, %MessageContext{} = ctx) do
    Friend.delete(req, ctx)
  end

  def execute(@friend_block, %FriendBlockReq{} = req, %MessageContext{} = ctx) do
    Friend.block(req, ctx)
  end

  def execute(@friend_unblock, %FriendUnblockReq{} = req, %MessageContext{} = ctx) do
    Friend.unblock(req, ctx)
  end

  def execute(@friend_remark, %FriendSetRemarkReq{} = req, %MessageContext{} = ctx) do
    Friend.set_remark(req, ctx)
  end

  def execute(@friend_list, %FriendListReq{} = req, %MessageContext{} = ctx) do
    Friend.list(req, ctx)
  end

  def execute(@friend_list, _payload, %MessageContext{} = ctx) do
    Friend.list(%FriendListReq{}, ctx)
  end

  def execute(@friend_request_list, %FriendRequestListReq{} = req, %MessageContext{} = ctx) do
    Friend.request_list(req, ctx)
  end

  def execute(@friend_request_list, _payload, %MessageContext{} = ctx) do
    Friend.request_list(%FriendRequestListReq{}, ctx)
  end

  def execute(:ack_local_data_cleared, _payload, %MessageContext{} = ctx) do
    DeviceBan.ack_local_data_cleared(ctx.app_key, ctx.user_id, ctx.device_id)
  end

  def execute(@channel_subscribe, %{channel_ids: ids} = payload, %MessageContext{} = ctx)
      when is_list(ids) do
    pubsub = Map.get(payload, :pubsub, false) == true
    Channel.subscribe(ids, ctx, pubsub: pubsub)
  end

  def execute(@channel_unsubscribe, %{channel_ids: ids} = payload, %MessageContext{} = ctx)
      when is_list(ids) do
    pubsub = Map.get(payload, :pubsub, false) == true
    Channel.unsubscribe(ids, ctx, pubsub: pubsub)
  end

  def execute(@channel_publish, %ChannelPublish{} = req, %MessageContext{} = ctx) do
    case Channel.publish_up(req, ctx) do
      :drop_silent -> {:ok, :drop_silent}
      other -> other
    end
  end

  def execute(:channel_publish_down, attrs, %MessageContext{} = ctx) when is_map(attrs) do
    channel_id = Map.get(attrs, :channel_id) || Map.get(attrs, "channel_id")
    caller =
      Map.get(attrs, :caller_service) || Map.get(attrs, "caller_service") ||
        ctx.caller_service || "unknown"

    app_key = Map.get(attrs, :app_key) || Map.get(attrs, "app_key") || ctx.app_key

    Channel.publish_down(app_key, channel_id, attrs, caller)
  end

  def execute(:group_mute, attrs, %MessageContext{} = ctx) when is_map(attrs) do
    group_id = Map.get(attrs, :group_id) || Map.get(attrs, "group_id")
    member_uid = Map.get(attrs, :member_uid) || Map.get(attrs, "member_uid")
    until = Map.get(attrs, :muted_until) || Map.get(attrs, "muted_until") || 0

    Group.mute_member(group_id, member_uid, until, ctx)
  end

  def execute(cmd, _payload, %MessageContext{}) when is_integer(cmd) do
    {:error, Error.not_implemented(cmd)}
  end

  def execute(_cmd, _payload, %MessageContext{}) do
    {:error, Error.new(:msg_invalid, "unknown dispatch command")}
  end
end
