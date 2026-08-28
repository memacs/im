defmodule IM.WebSocket.Commands.MsgRead do
  @moduledoc "`CMD_MSG_READ`。"

  alias IM.Delivery.Router
  alias IM.Domain.Error
  alias IM.Protocol.{Codec, Push, Reply}
  alias IM.Services.MessageRead
  alias IM.WebSocket.ConnectionState
  alias Pb.Im.Protocol.{CmdType, MsgRead, Packet}

  def handle(%Packet{} = packet, %ConnectionState{context: ctx} = state) when not is_nil(ctx) do
    with {:ok, %MsgRead{} = read} <- Codec.decode_payload(packet, MsgRead),
         {:ok, result} <- MessageRead.mark(read, ctx),
         {:ok, out} <-
           Push.build(:CMD_MSG_READ, result.read,
             trace_id: packet.trace_id,
             route_key: result.read.conv_id
           ) do
      if result.notify_user_id not in [nil, ""] do
        _ =
          Router.push_packet(out, ctx.app_key, result.notify_user_id, exclude_device_id: nil)
      end

      # 发送方其他设备同步已读
      _ =
        Router.push_packet(out, ctx.app_key, ctx.user_id,
          exclude_device_id: result.exclude_device_id
        )

      {:noreply, ConnectionState.touch(state)}
    else
      {:error, %Error{} = err} ->
        err = %{err | ref_cmd: CmdType.value(:CMD_MSG_READ)}

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
