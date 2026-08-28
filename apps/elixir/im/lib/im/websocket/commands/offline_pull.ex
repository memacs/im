defmodule IM.WebSocket.Commands.OfflinePull do
  @moduledoc "`CMD_OFFLINE_PULL_REQ` 薄适配。"

  alias IM.Domain.Error
  alias IM.Protocol.{Codec, Reply}
  alias IM.Services.Offline
  alias IM.WebSocket.ConnectionState
  alias Pb.Im.Protocol.{CmdType, OfflinePullReq, Packet}

  @doc false
  def handle(%Packet{} = packet, %ConnectionState{context: ctx} = state) when not is_nil(ctx) do
    with {:ok, %OfflinePullReq{} = req} <- Codec.decode_payload(packet, OfflinePullReq),
         {:ok, resp} <- Offline.pull(req, ctx),
         {:ok, out} <- Reply.ok(packet, :CMD_OFFLINE_PULL_RESP, resp),
         {:ok, bin} <- Codec.encode(out) do
      {:reply, bin, ConnectionState.touch(state)}
    else
      {:error, %Error{} = err} ->
        err = %{err | ref_cmd: CmdType.value(:CMD_OFFLINE_PULL_REQ)}

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
