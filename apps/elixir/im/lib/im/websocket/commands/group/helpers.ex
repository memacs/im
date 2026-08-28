defmodule IM.WebSocket.Commands.Group.Helpers do
  @moduledoc false

  alias IM.Delivery.Router
  alias IM.Domain.Error
  alias IM.Protocol.{Codec, Push, Reply}
  alias IM.WebSocket.ConnectionState
  @doc "CREATE：回 RESP。"
  def reply_resp(packet, state, resp_cmd, resp) do
    with {:ok, out} <- Reply.ok(packet, resp_cmd, resp),
         {:ok, bin} <- Codec.encode(out) do
      {:reply, bin, ConnectionState.touch(state)}
    else
      _ -> {:noreply, state}
    end
  end

  @doc "管理操作：回传 PUSH(seq) + 广播 PUSH(seq=0)。"
  def reply_push_and_broadcast(packet, state, result) do
    ctx = state.context
    push = result.push
    cmd = result.push_cmd

    with {:ok, broadcast} <-
           Push.build(cmd, push, trace_id: packet.trace_id, route_key: push.group_id),
         {:ok, ack} <- Reply.ok(packet, cmd, push),
         {:ok, ack_bin} <- Codec.encode(ack) do
      Enum.each(result.notify_user_ids, fn uid ->
        excl = if uid == ctx.user_id, do: result.exclude_device_id, else: nil
        _ = Router.push_packet(broadcast, ctx.app_key, uid, exclude_device_id: excl)
      end)

      {:reply, ack_bin, ConnectionState.touch(state)}
    else
      _ -> {:noreply, state}
    end
  end

  def reply_error(packet, state, err, ref_cmd) do
    err = %{err | ref_cmd: ref_cmd}

    case Reply.error(packet, err) do
      {:ok, out} ->
        {:ok, bin} = Codec.encode(out)
        {:reply, bin, state}

      _ ->
        {:noreply, state}
    end
  end

  def unauth_stop(state), do: {:stop, ConnectionState.closing(state)}

  def decode_error(%Error{} = err, packet, state, ref_cmd),
    do: reply_error(packet, state, err, ref_cmd)
end
