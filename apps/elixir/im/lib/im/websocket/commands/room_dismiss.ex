defmodule IM.WebSocket.Commands.RoomDismiss do
  @moduledoc "`CMD_ROOM_DISMISS_REQ`。"

  alias IM.Domain.Error
  alias IM.Protocol.{Codec, Push, Reply}
  alias IM.Room.PubSub, as: RoomPubSub
  alias IM.Services.Room
  alias IM.WebSocket.ConnectionState
  alias Pb.Im.Protocol.{CmdType, Packet, RoomOperateReq}

  def handle(%Packet{} = packet, %ConnectionState{context: ctx} = state) when not is_nil(ctx) do
    with {:ok, %RoomOperateReq{} = req} <- Codec.decode_payload(packet, RoomOperateReq),
         {:ok, result} <- Room.dismiss(req, ctx),
         {:ok, broadcast} <-
           Push.build(result.push_cmd, result.push,
             trace_id: packet.trace_id,
             route_key: result.room_id
           ),
         {:ok, bin} <- Codec.encode(broadcast),
         :ok <-
           RoomPubSub.broadcast(ctx.app_key, result.room_id, bin, %{
             exclude_device_id: ctx.device_id
           }),
         {:ok, ack} <- Reply.ok(packet, result.push_cmd, result.push),
         {:ok, ack_bin} <- Codec.encode(ack) do
      _ = RoomPubSub.unsubscribe(ctx.app_key, result.room_id)
      {:reply, ack_bin, ConnectionState.leave_room(state, result.room_id)}
    else
      {:error, %Error{} = err} ->
        err = %{err | ref_cmd: CmdType.value(:CMD_ROOM_DISMISS_REQ)}

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
