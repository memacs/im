defmodule IM.WebSocket.Commands.RoomLeave do
  @moduledoc "`CMD_ROOM_LEAVE_REQ`。"

  alias IM.Domain.Error
  alias IM.Protocol.{Codec, Push, Reply}
  alias IM.Room.PubSub, as: RoomPubSub
  alias IM.Services.Room
  alias IM.WebSocket.ConnectionState
  alias Pb.Im.Protocol.{CmdType, Packet, RoomOperateReq}

  def handle(%Packet{} = packet, %ConnectionState{context: ctx} = state) when not is_nil(ctx) do
    with {:ok, %RoomOperateReq{} = req} <- Codec.decode_payload(packet, RoomOperateReq),
         {:ok, push} <- Room.leave(req, ctx),
         {:ok, out} <-
           Push.build(:CMD_ROOM_LEAVE_PUSH, push,
             trace_id: packet.trace_id,
             route_key: req.room_id
           ),
         {:ok, out_bin} <- Codec.encode(out),
         :ok <-
           RoomPubSub.broadcast(ctx.app_key, req.room_id, out_bin, %{
             exclude_device_id: ctx.device_id
           }),
         :ok <- RoomPubSub.unsubscribe(ctx.app_key, req.room_id),
         {:ok, ack} <- Reply.ok(packet, :CMD_ROOM_LEAVE_PUSH, push),
         {:ok, bin} <- Codec.encode(ack) do
      {:reply, bin, ConnectionState.leave_room(state, req.room_id)}
    else
      {:error, %Error{} = err} ->
        err = %{err | ref_cmd: CmdType.value(:CMD_ROOM_LEAVE_REQ)}

        case Reply.error(packet, err) do
          {:ok, out} ->
            {:ok, bin} = Codec.encode(out)
            {:reply, bin, state}

          _ ->
            {:noreply, state}
        end
    end
  end

  def handle(_packet, state), do: {:stop, ConnectionState.closing(state)}
end
