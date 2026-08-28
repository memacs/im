defmodule IM.WebSocket.Commands.Friend.Unblock do
  @moduledoc "`CMD_FRIEND_UNBLOCK_REQ`。"

  alias IM.WebSocket.Commands.Friend.Helpers
  alias IM.WebSocket.ConnectionState
  alias Pb.Im.Protocol.{CmdType, Packet, FriendUnblockReq}

  def handle(%Packet{} = packet, %ConnectionState{context: ctx} = state) when not is_nil(ctx) do
    Helpers.handle_op(packet, state, FriendUnblockReq, CmdType.value(:CMD_FRIEND_UNBLOCK_REQ))
  end

  def handle(_packet, state), do: Helpers.unauth_stop(state)
end
