defmodule IM.WebSocket.Commands.RoomCreate do
  @moduledoc "`CMD_ROOM_CREATE_REQ`。"

  alias IM.Application.Dispatch
  alias IM.Domain.Error
  alias IM.Protocol.{Codec, Reply}
  alias IM.Room.PubSub, as: RoomPubSub
  alias IM.WebSocket.ConnectionState
  alias Pb.Im.Protocol.{CmdType, Packet, RoomCreateReq}

  def handle(%Packet{} = packet, %ConnectionState{context: ctx} = state) when not is_nil(ctx) do
    with {:ok, %RoomCreateReq{} = req} <- Codec.decode_payload(packet, RoomCreateReq),
         {:ok, resp} <- Dispatch.execute(CmdType.value(:CMD_ROOM_CREATE_REQ), req, ctx),
         :ok <- RoomPubSub.subscribe(ctx.app_key, resp.room_id),
         {:ok, out} <- Reply.ok(packet, :CMD_ROOM_CREATE_RESP, resp),
         {:ok, bin} <- Codec.encode(out) do
      {:reply, bin, ConnectionState.join_room(state, resp.room_id)}
    else
      {:error, %Error{} = err} ->
        err = %{err | ref_cmd: CmdType.value(:CMD_ROOM_CREATE_REQ)}

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
