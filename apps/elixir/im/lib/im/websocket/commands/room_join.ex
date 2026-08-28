defmodule IM.WebSocket.Commands.RoomJoin do
  @moduledoc "`CMD_ROOM_JOIN_REQ`。"

  alias IM.Application.Dispatch
  alias IM.Domain.Error
  alias IM.Protocol.{Codec, Push, Reply}
  alias IM.Room.PubSub, as: RoomPubSub
  alias IM.WebSocket.ConnectionState
  alias Pb.Im.Protocol.{CmdType, Packet, RoomOperateReq}

  def handle(%Packet{} = packet, %ConnectionState{context: ctx} = state) when not is_nil(ctx) do
    with {:ok, %RoomOperateReq{} = req} <- Codec.decode_payload(packet, RoomOperateReq),
         {:ok, push} <- Dispatch.execute(CmdType.value(:CMD_ROOM_JOIN_REQ), req, ctx),
         :ok <- RoomPubSub.subscribe(ctx.app_key, req.room_id),
         {:ok, out} <-
           Push.build(:CMD_ROOM_JOIN_PUSH, push,
             trace_id: packet.trace_id,
             route_key: req.room_id
           ),
         {:ok, out_bin} <- Codec.encode(out),
         :ok <-
           RoomPubSub.broadcast(ctx.app_key, req.room_id, out_bin, %{
             exclude_device_id: ctx.device_id
           }),
         # JOIN 响应用 PUSH 语义回客户端，并带上请求 seq 便于匹配
         {:ok, ack} <- Reply.ok(packet, :CMD_ROOM_JOIN_PUSH, push),
         {:ok, bin} <- Codec.encode(ack) do
      {:reply, bin, ConnectionState.join_room(state, req.room_id)}
    else
      {:error, %Error{} = err} ->
        err = %{err | ref_cmd: CmdType.value(:CMD_ROOM_JOIN_REQ)}

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
