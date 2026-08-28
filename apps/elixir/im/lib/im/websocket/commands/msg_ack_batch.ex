defmodule IM.WebSocket.Commands.MsgAckBatch do
  @moduledoc "`CMD_MSG_ACK_BATCH_UP`。"

  alias IM.Delivery.Router
  alias IM.Domain.Error
  alias IM.Protocol.{Codec, Push, Reply}
  alias IM.Services.Message
  alias IM.WebSocket.ConnectionState
  alias Pb.Im.Protocol.{CmdType, MsgAckBatchUp, Packet}

  def handle(%Packet{} = packet, %ConnectionState{context: ctx} = state) when not is_nil(ctx) do
    with {:ok, %MsgAckBatchUp{} = batch} <- Codec.decode_payload(packet, MsgAckBatchUp),
         {:ok, %{batches: batches}} <- Message.ack_batch_up(batch, ctx) do
      Enum.each(batches, fn {sender, down} ->
        case Push.build(:CMD_MSG_ACK_BATCH_DOWN, down, trace_id: packet.trace_id) do
          {:ok, out} -> _ = Router.push_packet(out, ctx.app_key, sender)
          _ -> :ok
        end
      end)

      {:noreply, ConnectionState.touch(state)}
    else
      {:error, %Error{} = err} ->
        err = %{err | ref_cmd: CmdType.value(:CMD_MSG_ACK_BATCH_UP)}

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
