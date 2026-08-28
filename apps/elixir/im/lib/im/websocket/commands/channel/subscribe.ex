defmodule IM.WebSocket.Commands.Channel.Subscribe do
  @moduledoc "`CMD_CHANNEL_SUBSCRIBE_REQ`（经 Dispatch）。"

  alias IM.Application.Dispatch
  alias IM.Domain.Error
  alias IM.Protocol.{Codec, Reply}
  alias IM.WebSocket.ConnectionState
  alias Pb.Im.Protocol.{ChannelSubscribeReq, CmdType, Packet}

  @doc false
  def handle(%Packet{} = packet, %ConnectionState{context: ctx} = state) when not is_nil(ctx) do
    cmd = CmdType.value(:CMD_CHANNEL_SUBSCRIBE_REQ)

    with {:ok, %ChannelSubscribeReq{channel_ids: ids}} <-
           Codec.decode_payload(packet, ChannelSubscribeReq),
         {:ok, resp} <- Dispatch.execute(cmd, %{channel_ids: ids, pubsub: true}, ctx),
         {:ok, out} <- Reply.ok(packet, :CMD_CHANNEL_SUBSCRIBE_RESP, resp),
         {:ok, bin} <- Codec.encode(out) do
      state2 =
        Enum.reduce(resp.subscribed, state, fn id, acc ->
          ConnectionState.join_channel(acc, id)
        end)

      {:reply, bin, ConnectionState.touch(state2)}
    else
      {:error, %Error{} = err} ->
        error_reply(packet, err, state)
    end
  end

  def handle(_packet, state), do: {:stop, ConnectionState.closing(state)}

  defp error_reply(packet, err, state) do
    err = %{err | ref_cmd: CmdType.value(:CMD_CHANNEL_SUBSCRIBE_REQ)}

    case Reply.error(packet, err) do
      {:ok, out} ->
        {:ok, bin} = Codec.encode(out)
        {:reply, bin, state}

      _ ->
        {:noreply, state}
    end
  end
end
