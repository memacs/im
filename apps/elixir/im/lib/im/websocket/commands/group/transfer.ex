defmodule IM.WebSocket.Commands.Group.Transfer do
  @moduledoc "`CMD_GROUP_TRANSFER_REQ`。"

  alias IM.Domain.Error
  alias IM.Protocol.Codec
  alias IM.Services.Group
  alias IM.WebSocket.Commands.Group.Helpers
  alias IM.WebSocket.ConnectionState
  alias Pb.Im.Protocol.{CmdType, GroupTransferReq, Packet}

  def handle(%Packet{} = packet, %ConnectionState{context: ctx} = state) when not is_nil(ctx) do
    with {:ok, %GroupTransferReq{} = req} <- Codec.decode_payload(packet, GroupTransferReq),
         {:ok, result} <- Group.transfer(req, ctx) do
      Helpers.reply_push_and_broadcast(packet, state, result)
    else
      {:error, %Error{} = err} ->
        Helpers.reply_error(packet, state, err, CmdType.value(:CMD_GROUP_TRANSFER_REQ))
    end
  end

  def handle(_packet, state), do: Helpers.unauth_stop(state)
end
