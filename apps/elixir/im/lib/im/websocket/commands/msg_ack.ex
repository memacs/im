defmodule IM.WebSocket.Commands.MsgAck do
  @moduledoc "`CMD_MSG_ACK_UP` 薄适配。"

  alias IM.Delivery.Router
  alias IM.Domain.Error
  alias IM.Protocol.{Codec, Push, Reply}
  alias IM.Services.Message
  alias IM.WebSocket.ConnectionState
  alias Pb.Im.Protocol.{CmdType, MsgAck, Packet}

  @doc false
  def handle(%Packet{} = packet, %ConnectionState{context: ctx} = state) when not is_nil(ctx) do
    with {:ok, %MsgAck{} = ack} <- Codec.decode_payload(packet, MsgAck),
         {:ok, %{ack_down: down, sender_user_id: sender}} <- Message.ack_up(ack, ctx),
         {:ok, out} <-
           Push.build(:CMD_MSG_ACK_DOWN, down, trace_id: packet.trace_id, route_key: "") do
      _ = Router.push_packet(out, ctx.app_key, sender)
      {:noreply, ConnectionState.touch(state)}
    else
      {:error, %Error{} = err} ->
        err = %{err | ref_cmd: CmdType.value(:CMD_MSG_ACK_UP)}

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
