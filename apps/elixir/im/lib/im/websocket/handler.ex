defmodule IM.WebSocket.Handler do
  @moduledoc """
  解码后的 `Packet` 分发到 `Commands.*`，并统一构造回复二进制。
  """

  require IM.Log

  alias IM.Domain.Error
  alias IM.Protocol.{Codec, ErrorCodes, Reply, Router}
  alias IM.Telemetry.Websocket, as: WsTelemetry
  alias IM.WebSocket.ConnectionState
  alias Pb.Im.Protocol.Packet

  @doc """
  处理一帧业务包。

  返回：
  - `{:reply, binary, state}`
  - `{:reply_close, binary, state}`
  - `{:noreply, state}`
  - `{:stop, state}`

  ## 示例

      IM.WebSocket.Handler.handle_packet(packet, conn_state)
  """
  @spec handle_packet(Packet.t(), ConnectionState.t()) ::
          {:reply, binary(), ConnectionState.t()}
          | {:reply_close, binary(), ConnectionState.t()}
          | {:noreply, ConnectionState.t()}
          | {:stop, ConnectionState.t()}
  def handle_packet(%Packet{} = packet, %ConnectionState{} = state) do
    start = System.monotonic_time()
    _ = IM.Log.Metadata.set_from_packet(packet, state)
    WsTelemetry.frame_in(byte_size(Packet.encode(packet)), packet.cmd)

    result =
      try do
        case ConnectionState.allow?(state, packet.cmd) do
          :ok ->
            dispatch(packet, state)

          {:error, :silent_close} ->
            {:stop, ConnectionState.closing(state)}

          {:error, :already_authenticated} ->
            error_close(
              packet,
              state,
              Error.new(:unauthorized, "already_authenticated", ref_cmd: packet.cmd)
            )

          {:error, :invalid_cmd} ->
            error_close(
              packet,
              state,
              Error.new(:msg_invalid, "invalid_cmd_in_state", ref_cmd: packet.cmd)
            )
        end
      rescue
        e ->
          IM.Log.error(:handler_crash,
            cmd: packet.cmd,
            reason: Exception.message(e)
          )

          {:stop, ConnectionState.closing(state)}
      end

    WsTelemetry.handler_stop(start, packet.cmd, handler_result(result))
    result
  end

  defp dispatch(packet, state) do
    with {:ok, mod} <- Router.route(packet.cmd) do
      mod.handle(packet, state)
    else
      {:error, %Error{} = err} ->
        error_close(packet, state, err)
    end
  end

  defp error_close(packet, state, %Error{} = err) do
    code = ErrorCodes.to_int(err.code)
    ref = ref_cmd_name(err.ref_cmd || packet.cmd)

    IM.Log.warning(:packet_error,
      code: code,
      ref_cmd: ref,
      reason: err.msg || Atom.to_string(err.code)
    )

    WsTelemetry.packet_error(code, ref)

    case Reply.error(packet, err) do
      {:ok, resp} ->
        {:ok, bin} = Codec.encode(resp)
        WsTelemetry.frame_out(byte_size(bin), resp.cmd)
        {:reply_close, bin, ConnectionState.closing(state)}

      {:error, _} ->
        {:stop, ConnectionState.closing(state)}
    end
  end

  defp ref_cmd_name(cmd) when is_integer(cmd) do
    case IM.Protocol.Cmd.to_atom(cmd) do
      {:ok, atom} -> Atom.to_string(atom)
      _ -> Integer.to_string(cmd)
    end
  end

  defp ref_cmd_name(cmd) when is_atom(cmd), do: Atom.to_string(cmd)
  defp ref_cmd_name(_), do: "unknown"

  defp handler_result({:reply_close, _, _}), do: :error
  defp handler_result({:stop, _}), do: :stop
  defp handler_result(_), do: :ok
end
