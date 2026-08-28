defmodule IM.WebSocket.Commands.Heartbeat do
  @moduledoc "`CMD_HEARTBEAT_REQ` 薄适配。"

  alias IM.Domain.Error
  alias IM.Protocol.{Codec, Reply}
  alias IM.Services.Heartbeat
  alias IM.Telemetry.Message, as: MsgTelemetry
  alias IM.Telemetry.Websocket, as: WsTelemetry
  alias IM.WebSocket.ConnectionState
  alias Pb.Im.Protocol.{HeartbeatReq, Packet}

  @doc """
  处理心跳。

  ## 示例

      IM.WebSocket.Commands.Heartbeat.handle(packet, state)
  """
  @spec handle(Packet.t(), ConnectionState.t()) ::
          {:reply, binary(), ConnectionState.t()} | {:stop, ConnectionState.t()}
  def handle(%Packet{} = packet, %ConnectionState{context: ctx} = state) when not is_nil(ctx) do
    start = System.monotonic_time()

    with {:ok, %HeartbeatReq{} = req} <- Codec.decode_payload(packet, HeartbeatReq),
         {:ok, resp} <- Heartbeat.beat(req, ctx),
         {:ok, out} <- Reply.ok(packet, :CMD_HEARTBEAT_RESP, resp),
         {:ok, bin} <- Codec.encode(out) do
      WsTelemetry.frame_out(byte_size(bin), out.cmd)
      MsgTelemetry.ack_latency(:heartbeat_rtt, start, :none, :unknown)
      {:reply, bin, ConnectionState.touch(state)}
    else
      {:error, %Error{}} ->
        {:stop, ConnectionState.closing(state)}

      {:error, _} ->
        {:stop, ConnectionState.closing(state)}
    end
  end

  def handle(_packet, state), do: {:stop, ConnectionState.closing(state)}
end
