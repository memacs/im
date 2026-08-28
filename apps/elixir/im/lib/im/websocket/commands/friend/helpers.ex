defmodule IM.WebSocket.Commands.Friend.Helpers do
  @moduledoc false

  alias IM.Application.Dispatch
  alias IM.Delivery.Router
  alias IM.Domain.Error
  alias IM.Protocol.{Codec, Push, Reply}
  alias IM.WebSocket.ConnectionState

  def handle_op(packet, state, decode_mod, ref_cmd) do
    ctx = state.context

    with {:ok, req} <- Codec.decode_payload(packet, decode_mod),
         {:ok, result} <- Dispatch.execute(ref_cmd, req, ctx),
         {:ok, ack} <- Reply.ok(packet, result.resp_cmd, result.resp),
         {:ok, ack_bin} <- Codec.encode(ack) do
      maybe_push(packet, ctx, result)
      {:reply, ack_bin, ConnectionState.touch(state)}
    else
      {:error, %Error{} = err} ->
        err = %{err | ref_cmd: ref_cmd}

        case Reply.error(packet, err) do
          {:ok, out} ->
            {:ok, bin} = Codec.encode(out)
            {:reply, bin, state}

          _ ->
            {:noreply, state}
        end
    end
  end

  defp maybe_push(_packet, _ctx, %{notify: nil}), do: :ok
  defp maybe_push(_packet, _ctx, %{push_cmd: nil}), do: :ok

  defp maybe_push(packet, ctx, result) do
    case Push.build(result.push_cmd, result.notify, trace_id: packet.trace_id) do
      {:ok, out} ->
        _ = Router.push_packet(out, ctx.app_key, result.notify_user_id)

      _ ->
        :ok
    end
  end

  def unauth_stop(state), do: {:stop, ConnectionState.closing(state)}
end
