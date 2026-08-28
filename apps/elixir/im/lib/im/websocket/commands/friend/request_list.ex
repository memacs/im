defmodule IM.WebSocket.Commands.Friend.RequestList do
  @moduledoc "`CMD_FRIEND_REQUEST_LIST_REQ`。"

  alias IM.WebSocket.Commands.Friend.Helpers
  alias IM.WebSocket.ConnectionState
  alias Pb.Im.Protocol.{CmdType, Packet, FriendRequestListReq}

  def handle(%Packet{} = packet, %ConnectionState{context: ctx} = state) when not is_nil(ctx) do
    Helpers.handle_op(
      packet,
      state,
      FriendRequestListReq,
      CmdType.value(:CMD_FRIEND_REQUEST_LIST_REQ)
    )
  end

  def handle(_packet, state), do: Helpers.unauth_stop(state)
end
