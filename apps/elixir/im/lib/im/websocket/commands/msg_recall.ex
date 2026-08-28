defmodule IM.WebSocket.Commands.MsgRecall do
  @moduledoc "`CMD_MSG_RECALL_REQ`。"

  alias IM.Delivery.Router
  alias IM.Domain.Error
  alias IM.Protocol.{Codec, Push, Reply}
  alias IM.Services.MessageRecall
  alias IM.WebSocket.ConnectionState
  alias Pb.Im.Protocol.{CmdType, MsgRecall, Packet}

  def handle(%Packet{} = packet, %ConnectionState{context: ctx} = state) when not is_nil(ctx) do
    with {:ok, %MsgRecall{} = req} <- Codec.decode_payload(packet, MsgRecall),
         {:ok, result} <- MessageRecall.recall(req, ctx),
         {:ok, out} <-
           Push.build(:CMD_MSG_RECALL_PUSH, result.recall,
             trace_id: packet.trace_id,
             route_key: result.recall.conv_id
           ),
         {:ok, ack} <- Reply.ok(packet, :CMD_MSG_RECALL_PUSH, result.recall),
         {:ok, ack_bin} <- Codec.encode(ack) do
      Enum.each(result.recipient_user_ids, fn uid ->
        excl = if uid == ctx.user_id, do: result.exclude_device_id, else: nil
        _ = Router.push_packet(out, ctx.app_key, uid, exclude_device_id: excl)
      end)

      {:reply, ack_bin, ConnectionState.touch(state)}
    else
      {:error, %Error{} = err} ->
        err = %{err | ref_cmd: CmdType.value(:CMD_MSG_RECALL_REQ)}

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
