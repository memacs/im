defmodule IM.WebSocket.Commands.Channel.Publish do
  @moduledoc "`CMD_CHANNEL_PUBLISH`（经 Dispatch；超限静默丢弃）。"

  alias IM.Application.Dispatch
  alias IM.Domain.Error
  alias IM.Protocol.{Codec, Reply}
  alias IM.WebSocket.ConnectionState
  alias Pb.Im.Protocol.{ChannelPublish, CmdType, Packet}

  @doc false
  def handle(%Packet{} = packet, %ConnectionState{context: ctx} = state) when not is_nil(ctx) do
    cmd = CmdType.value(:CMD_CHANNEL_PUBLISH)

    with {:ok, %ChannelPublish{} = req} <- Codec.decode_payload(packet, ChannelPublish) do
      case Dispatch.execute(cmd, req, ctx) do
        {:ok, :drop_silent} ->
          {:noreply, ConnectionState.touch(state)}

        {:ok, ack} ->
          with {:ok, out} <- Reply.ok(packet, :CMD_CHANNEL_PUBLISH_ACK, ack),
               {:ok, bin} <- Codec.encode(out) do
            {:reply, bin, ConnectionState.touch(state)}
          else
            _ -> {:noreply, state}
          end

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
