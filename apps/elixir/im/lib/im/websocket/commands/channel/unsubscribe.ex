defmodule IM.WebSocket.Commands.Channel.Unsubscribe do
  @moduledoc "`CMD_CHANNEL_UNSUBSCRIBE_REQ`（经 Dispatch）。"

  alias IM.Application.Dispatch
  alias IM.Domain.Error
  alias IM.Protocol.{Codec, Reply}
  alias IM.WebSocket.ConnectionState
  alias Pb.Im.Protocol.{ChannelUnsubscribeReq, CmdType, Packet}

  @doc false
  def handle(%Packet{} = packet, %ConnectionState{context: ctx} = state) when not is_nil(ctx) do
    cmd = CmdType.value(:CMD_CHANNEL_UNSUBSCRIBE_REQ)

    with {:ok, %ChannelUnsubscribeReq{channel_ids: ids}} <-
           Codec.decode_payload(packet, ChannelUnsubscribeReq),
         {:ok, resp} <- Dispatch.execute(cmd, %{channel_ids: ids, pubsub: true}, ctx),
         {:ok, out} <- Reply.ok(packet, :CMD_CHANNEL_UNSUBSCRIBE_RESP, resp),
         {:ok, bin} <- Codec.encode(out) do
      state2 =
        Enum.reduce(resp.unsubscribed, state, fn id, acc ->
          ConnectionState.leave_channel(acc, id)
        end)

      {:reply, bin, ConnectionState.touch(state2)}
    else
      {:error, %Error{} = err} ->
        err = %{err | ref_cmd: cmd}

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
