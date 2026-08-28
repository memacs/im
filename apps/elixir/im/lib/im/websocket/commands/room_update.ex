defmodule IM.WebSocket.Commands.RoomUpdate do
  @moduledoc "`CMD_ROOM_UPDATE_REQ`。"

  alias IM.Domain.Error
  alias IM.Protocol.{Codec, Push, Reply}
  alias IM.Room.PubSub, as: RoomPubSub
  alias IM.Services.Room
  alias IM.WebSocket.ConnectionState
  alias Pb.Im.Protocol.{CmdType, Packet, RoomUpdateReq}

  def handle(%Packet{} = packet, %ConnectionState{context: ctx} = state) when not is_nil(ctx) do
    with {:ok, %RoomUpdateReq{} = req} <- Codec.decode_payload(packet, RoomUpdateReq),
         {:ok, result} <- Room.update(req, ctx),
         {:ok, broadcast} <-
           Push.build(result.push_cmd, result.push,
             trace_id: packet.trace_id,
             route_key: result.room_id
           ),
         {:ok, bin} <- Codec.encode(broadcast),
         :ok <- RoomPubSub.broadcast(ctx.app_key, result.room_id, bin, %{exclude_device_id: ctx.device_id}),
         {:ok, ack} <- Reply.ok(packet, result.push_cmd, result.push),
         {:ok, ack_bin} <- Codec.encode(ack) do
      {:reply, ack_bin, ConnectionState.touch(state)}
    else
      {:error, %Error{} = err} ->
        err = %{err | ref_cmd: CmdType.value(:CMD_ROOM_UPDATE_REQ)}

        case Reply.error(packet, err) do
          {:ok, out} ->
            {:ok, b} = Codec.encode(out)
            {:reply, b, state}

          _ ->
            {:noreply, state}
        end
    end
  end

  def handle(_packet, state), do: {:stop, ConnectionState.closing(state)}
end
