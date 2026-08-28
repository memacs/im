defmodule IM.WebSocket.Commands.Friend.Reject do
  @moduledoc "`CMD_FRIEND_REJECT_REQ`。"

  alias IM.WebSocket.Commands.Friend.Helpers
  alias IM.WebSocket.ConnectionState
  alias Pb.Im.Protocol.{CmdType, Packet, FriendRejectReq}

  def handle(%Packet{} = packet, %ConnectionState{context: ctx} = state) when not is_nil(ctx) do
    Helpers.handle_op(packet, state, FriendRejectReq, CmdType.value(:CMD_FRIEND_REJECT_REQ))
  end

  def handle(_packet, state), do: Helpers.unauth_stop(state)
end
