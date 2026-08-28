defmodule IM.WebSocket.Commands.Friend.Accept do
  @moduledoc "`CMD_FRIEND_ACCEPT_REQ`。"

  alias IM.WebSocket.Commands.Friend.Helpers
  alias IM.WebSocket.ConnectionState
  alias Pb.Im.Protocol.{CmdType, Packet, FriendAcceptReq}

  def handle(%Packet{} = packet, %ConnectionState{context: ctx} = state) when not is_nil(ctx) do
    Helpers.handle_op(packet, state, FriendAcceptReq, CmdType.value(:CMD_FRIEND_ACCEPT_REQ))
  end

  def handle(_packet, state), do: Helpers.unauth_stop(state)
end
