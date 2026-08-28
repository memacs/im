defmodule IM.Protocol.Router do
  @moduledoc """
  WS 侧按 `cmd` 选择 `IM.WebSocket.Commands.*` 处理模块。

  **本模块不含业务**：业务在 `IM.Services.*`，经 `IM.Application.Dispatch` 或 Command 内调用。
  """

  alias IM.Domain.Error
  alias Pb.Im.Protocol.CmdType

  @default_handlers %{
    CmdType.value(:CMD_AUTH_REQ) => IM.WebSocket.Commands.Auth,
    CmdType.value(:CMD_HEARTBEAT_REQ) => IM.WebSocket.Commands.Heartbeat,
    CmdType.value(:CMD_MSG_SEND) => IM.WebSocket.Commands.MsgSend,
    CmdType.value(:CMD_MSG_ACK_UP) => IM.WebSocket.Commands.MsgAck,
    CmdType.value(:CMD_OFFLINE_PULL_REQ) => IM.WebSocket.Commands.OfflinePull,
    CmdType.value(:CMD_ROOM_CREATE_REQ) => IM.WebSocket.Commands.RoomCreate,
    CmdType.value(:CMD_ROOM_JOIN_REQ) => IM.WebSocket.Commands.RoomJoin,
    CmdType.value(:CMD_ROOM_LEAVE_REQ) => IM.WebSocket.Commands.RoomLeave,
    CmdType.value(:CMD_ROOM_DISMISS_REQ) => IM.WebSocket.Commands.RoomDismiss,
    CmdType.value(:CMD_ROOM_KICK_REQ) => IM.WebSocket.Commands.RoomKick,
    CmdType.value(:CMD_ROOM_UPDATE_REQ) => IM.WebSocket.Commands.RoomUpdate,
    CmdType.value(:CMD_GROUP_CREATE_REQ) => IM.WebSocket.Commands.Group.Create,
    CmdType.value(:CMD_GROUP_DISMISS_REQ) => IM.WebSocket.Commands.Group.Dismiss,
    CmdType.value(:CMD_GROUP_JOIN_REQ) => IM.WebSocket.Commands.Group.Join,
    CmdType.value(:CMD_GROUP_LEAVE_REQ) => IM.WebSocket.Commands.Group.Leave,
    CmdType.value(:CMD_GROUP_KICK_REQ) => IM.WebSocket.Commands.Group.Kick,
    CmdType.value(:CMD_GROUP_INVITE_REQ) => IM.WebSocket.Commands.Group.Invite,
    CmdType.value(:CMD_GROUP_SET_ADMIN_REQ) => IM.WebSocket.Commands.Group.SetAdmin,
    CmdType.value(:CMD_GROUP_REMOVE_ADMIN_REQ) => IM.WebSocket.Commands.Group.RemoveAdmin,
    CmdType.value(:CMD_GROUP_TRANSFER_REQ) => IM.WebSocket.Commands.Group.Transfer,
    CmdType.value(:CMD_GROUP_UPDATE_REQ) => IM.WebSocket.Commands.Group.Update,
    CmdType.value(:CMD_MSG_ACK_BATCH_UP) => IM.WebSocket.Commands.MsgAckBatch,
    CmdType.value(:CMD_MSG_READ) => IM.WebSocket.Commands.MsgRead,
    CmdType.value(:CMD_MSG_RECALL_REQ) => IM.WebSocket.Commands.MsgRecall,
    CmdType.value(:CMD_MSG_EDIT_REQ) => IM.WebSocket.Commands.MsgEdit,
    CmdType.value(:CMD_PASSTHROUGH) => IM.WebSocket.Commands.Passthrough,
    CmdType.value(:CMD_FRIEND_ADD_REQ) => IM.WebSocket.Commands.Friend.Add,
    CmdType.value(:CMD_FRIEND_ACCEPT_REQ) => IM.WebSocket.Commands.Friend.Accept,
    CmdType.value(:CMD_FRIEND_REJECT_REQ) => IM.WebSocket.Commands.Friend.Reject,
    CmdType.value(:CMD_FRIEND_DELETE_REQ) => IM.WebSocket.Commands.Friend.Delete,
    CmdType.value(:CMD_FRIEND_BLOCK_REQ) => IM.WebSocket.Commands.Friend.Block,
    CmdType.value(:CMD_FRIEND_UNBLOCK_REQ) => IM.WebSocket.Commands.Friend.Unblock,
    CmdType.value(:CMD_FRIEND_SET_REMARK_REQ) => IM.WebSocket.Commands.Friend.SetRemark,
    CmdType.value(:CMD_FRIEND_LIST_REQ) => IM.WebSocket.Commands.Friend.List,
    CmdType.value(:CMD_FRIEND_REQUEST_LIST_REQ) => IM.WebSocket.Commands.Friend.RequestList,
    CmdType.value(:CMD_CHANNEL_SUBSCRIBE_REQ) => IM.WebSocket.Commands.Channel.Subscribe,
    CmdType.value(:CMD_CHANNEL_UNSUBSCRIBE_REQ) => IM.WebSocket.Commands.Channel.Unsubscribe,
    CmdType.value(:CMD_CHANNEL_PUBLISH) => IM.WebSocket.Commands.Channel.Publish
  }

  @doc """
  返回处理该 `cmd` 的 Command 模块。

  ## 示例

      {:ok, IM.WebSocket.Commands.Auth} = IM.Protocol.Router.route(1)
  """
  @spec route(non_neg_integer()) :: {:ok, module()} | {:error, Error.t()}
  def route(cmd) when is_integer(cmd) and cmd >= 0 do
    case Map.fetch(handlers(), cmd) do
      {:ok, mod} when is_atom(mod) ->
        {:ok, mod}

      :error ->
        {:error, Error.new(:unknown_cmd, "unregistered cmd: #{cmd}", ref_cmd: cmd)}
    end
  end

  @doc """
  当前生效的 cmd → 模块表。

  ## 示例

      map = IM.Protocol.Router.handlers()
  """
  @spec handlers() :: %{optional(non_neg_integer()) => module()}
  def handlers do
    Map.merge(@default_handlers, Application.get_env(:im, :protocol_command_handlers, %{}))
  end
end
