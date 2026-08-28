defmodule IM.WebSocket.Commands.Passthrough do
  @moduledoc "`CMD_PASSTHROUGH`（含流式透传 action）。"

  alias IM.Delivery.Router
  alias IM.Domain.Error
  alias IM.Protocol.{Codec, Push, Reply}
  alias IM.Services.Passthrough, as: PassthroughService
  alias IM.WebSocket.ConnectionState
  alias Pb.Im.Protocol.{CmdType, Packet, Passthrough}

  def handle(%Packet{} = packet, %ConnectionState{context: ctx} = state) when not is_nil(ctx) do
    with {:ok, %Passthrough{} = pt} <- Codec.decode_payload(packet, Passthrough),
         {:ok, result} <- PassthroughService.send(pt, ctx),
         {:ok, out} <-
           Push.build(:CMD_PASSTHROUGH, result.passthrough,
             trace_id: packet.trace_id,
             route_key: result.passthrough.conv_id || ""
           ) do
      Enum.each(result.recipient_user_ids, fn uid ->
        excl = if uid == ctx.user_id, do: result.exclude_device_id, else: nil
        _ = Router.push_packet(out, ctx.app_key, uid, exclude_device_id: excl)
      end)

      {:noreply, ConnectionState.touch(state)}
    else
      {:error, %Error{} = err} ->
        err = %{err | ref_cmd: CmdType.value(:CMD_PASSTHROUGH)}

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
