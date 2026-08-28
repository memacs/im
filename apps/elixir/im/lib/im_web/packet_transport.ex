defmodule IMWeb.PacketTransport do
  @moduledoc """
  二进制 `Packet` WebSocket 传输（WebSock），路径 `/ws`。

  不使用 Phoenix Channel 帧；客户端直接收发 Protobuf `Packet` 字节。
  出站经 `IM.Delivery.OutboundQueue`（WFQ + 老化）。
  """

  @behaviour WebSock

  require IM.Log

  alias IM.Delivery.ChannelRouter
  alias IM.Delivery.OutboundQueue
  alias IM.Protocol.Codec
  alias IM.Stores.UserDeviceStore
  alias IM.WebSocket.{ConnectionState, Handler, TokenExpiry}

  @impl true
  def init(_opts) do
    timeout = Application.get_env(:im, :auth_timeout_ms, 10_000)
    auth_timer = Process.send_after(self(), :auth_timeout, timeout)
    IM.Telemetry.Connection.opened()

    {:ok,
     %{
       conn: ConnectionState.new(),
       auth_timer: auth_timer,
       idle_timer: nil,
       token_timer: nil,
       outbound: OutboundQueue.new()
     }}
  end

  @impl true
  def handle_in({data, [opcode: :binary]}, state) when is_binary(data) do
    case Codec.decode(data) do
      {:ok, packet} ->
        state = cancel_auth_timer_if_needed(state)

        case Handler.handle_packet(packet, state.conn) do
          {:reply, bin, conn} ->
            state =
              state
              |> Map.put(:conn, conn)
              |> refresh_idle()
              |> maybe_schedule_token_expiry()

            {:push, {:binary, bin}, state}

          {:reply_close, bin, conn} ->
            {:stop, :normal, 1000, {:binary, bin}, %{state | conn: conn}}

          {:noreply, conn} ->
            state =
              state
              |> Map.put(:conn, conn)
              |> refresh_idle()
              |> maybe_schedule_token_expiry()

            {:ok, state}

          {:stop, conn} ->
            {:stop, :normal, %{state | conn: conn}}
        end

      {:error, reason} ->
        IM.Log.error(:packet_decode_error,
          reason: "decode_failed size=#{byte_size(data)}: #{inspect(reason)}"
        )

        {:stop, :normal, %{state | conn: ConnectionState.closing(state.conn)}}
    end
  end

  def handle_in({_data, [opcode: :text]}, state) do
    IM.Log.error(:packet_decode_error, reason: "text_frame_not_allowed")
    {:stop, :normal, %{state | conn: ConnectionState.closing(state.conn)}}
  end

  @impl true
  def handle_info(:auth_timeout, %{conn: %{status: :unauthenticated}} = state) do
    {:stop, :normal, %{state | conn: ConnectionState.closing(state.conn)}}
  end

  def handle_info(:auth_timeout, state), do: {:ok, state}

  def handle_info(:idle_timeout, %{conn: %{status: :authenticated}} = state) do
    {:stop, :normal, %{state | conn: ConnectionState.closing(state.conn)}}
  end

  def handle_info(:idle_timeout, state), do: {:ok, state}

  def handle_info(:token_expired, %{conn: %{status: :authenticated}} = state) do
    :ok = TokenExpiry.kick_expired!(state.conn)
    {:ok, state}
  end

  def handle_info(:token_expired, state), do: {:ok, state}

  def handle_info({:im_kick, packet}, state) do
    case Codec.encode(packet) do
      {:ok, bin} ->
        {:stop, :normal, 1000, {:binary, bin},
         %{state | conn: ConnectionState.closing(state.conn)}}

      {:error, _} ->
        {:stop, :normal, %{state | conn: ConnectionState.closing(state.conn)}}
    end
  end

  def handle_info({:im_push, bin}, state) when is_binary(bin) do
    handle_info({:im_push, bin, %{}}, state)
  end

  def handle_info({:im_push, bin, meta}, state) when is_binary(bin) and is_map(meta) do
    push_via_queue(state, bin, meta)
  end

  def handle_info({:im_room_push, bin, meta}, state) when is_binary(bin) and is_map(meta) do
    if room_deliver?(state.conn, meta) do
      push_via_queue(state, bin, meta)
    else
      {:ok, state}
    end
  end

  def handle_info({:channel_push, bin}, state) when is_binary(bin) do
    # App Channel 可丢；走 LOW 带（超 outbound_max_depth 时优先丢弃）
    push_via_queue(state, bin, %{priority: :low})
  end

  def handle_info(_msg, state), do: {:ok, state}

  @impl true
  def terminate(_reason, state) do
    cancel_token_timer(state)

    case state.conn do
      %{status: :authenticated, context: %{app_key: a, user_id: u, device_id: d} = ctx} ->
        _ = UserDeviceStore.set_online(a, u, d, false)
        unsubscribe_channels(ctx.app_key, state.conn.channels)

        _ = IM.EventBus.Session.logout(ctx, "ws_disconnect")

        IM.Audit.record(:auth_logout,
          app_key: a,
          user_id: u,
          device_id: d,
          strategy: "token",
          result: :success,
          reason: "ws_disconnect"
        )

      _ ->
        :ok
    end

    :ok
  end

  defp push_via_queue(state, bin, meta) do
    priority = Map.get(meta, :priority, :normal)

    # 队列空时 HIGH 可直写，降低紧急推送延迟
    if OutboundQueue.empty?(state.outbound) and
         OutboundQueue.normalize_priority(priority) == :high do
      {:push, {:binary, bin}, refresh_idle(state)}
    else
      item = %{
        packet_binary: bin,
        priority: priority,
        inbox_seq: Map.get(meta, :inbox_seq, 0) || 0,
        enqueued_at_ms: System.system_time(:millisecond)
      }

      q = OutboundQueue.enqueue(state.outbound, item)
      max_burst = Application.get_env(:im, :priority_max_burst, 16)
      {bins, q2} = OutboundQueue.drain(q, max_burst)

      IM.Telemetry.Outbound.depth(%{
        high: length(q2.high),
        normal: length(q2.normal),
        low: length(q2.low)
      })

      state = refresh_idle(%{state | outbound: q2})
      push_bins(bins, state)
    end
  end

  defp push_bins([], state), do: {:ok, state}
  defp push_bins([bin], state), do: {:push, {:binary, bin}, state}

  defp push_bins(bins, state) do
    frames = Enum.map(bins, &{:binary, &1})
    {:push, frames, state}
  end

  defp unsubscribe_channels(app_key, channels) do
    Enum.each(channels, fn ch -> ChannelRouter.unsubscribe(app_key, ch) end)
  end

  defp cancel_auth_timer_if_needed(%{auth_timer: nil} = state), do: state

  defp cancel_auth_timer_if_needed(%{auth_timer: ref} = state) do
    Process.cancel_timer(ref)
    %{state | auth_timer: nil}
  end

  defp refresh_idle(%{conn: %{status: :authenticated}} = state) do
    if state.idle_timer, do: Process.cancel_timer(state.idle_timer)
    idle = Application.get_env(:im, :idle_timeout_ms, 90_000)
    ref = Process.send_after(self(), :idle_timeout, idle)
    %{state | idle_timer: ref, conn: ConnectionState.touch(state.conn)}
  end

  defp refresh_idle(state), do: state

  defp maybe_schedule_token_expiry(
         %{conn: %ConnectionState{status: :authenticated, token_expires_at: exp}} = state
       )
       when not is_nil(exp) do
    {state, _ref} = TokenExpiry.schedule(state, state.conn)
    state
  end

  defp maybe_schedule_token_expiry(state), do: state

  defp cancel_token_timer(%{token_timer: ref}) when is_reference(ref) do
    Process.cancel_timer(ref)
    :ok
  end

  defp cancel_token_timer(_), do: :ok

  defp room_deliver?(%{context: nil}, _meta), do: false

  defp room_deliver?(%{context: ctx}, meta) do
    exclude = Map.get(meta, :exclude_device_id)
    sender = Map.get(meta, :sender_user_id)
    targets = Map.get(meta, :target_users) || []

    cond do
      exclude && sender == ctx.user_id && exclude == ctx.device_id ->
        false

      targets != [] and ctx.user_id not in targets and ctx.user_id != sender ->
        false

      true ->
        true
    end
  end
end
