defmodule IM.WebSocket.TokenExpiry do
  @moduledoc """
  已鉴权长连接上的 token 过期调度（protocol §5 / auth.md §9）。

  AUTH 成功时按 `expires_at` 安排 `:token_expired`；到期下发 `CMD_KICK(token_expired)`。
  """

  alias IM.Services.Kick
  alias IM.WebSocket.ConnectionState
  alias Pb.Im.Protocol.KickReason

  @doc """
  计算距 `expires_at` 的毫秒延迟；已过期返回 `0`。

  ## 示例

      IM.WebSocket.TokenExpiry.delay_ms(~U[2030-01-01 00:00:00Z])
  """
  @spec delay_ms(DateTime.t(), DateTime.t()) :: non_neg_integer()
  def delay_ms(%DateTime{} = expires_at, %DateTime{} = now \\ DateTime.utc_now()) do
    max(0, DateTime.diff(expires_at, now, :millisecond))
  end

  @doc """
  为已鉴权连接安排 token 过期定时器；取消旧定时器（若有）。

  返回 `{state, timer_ref}`，`timer_ref` 为 `nil` 或 `reference()`。
  """
  @spec schedule(map(), ConnectionState.t()) :: {map(), reference() | nil}
  def schedule(%{token_timer: prev} = state, %ConnectionState{} = conn) do
    if is_reference(prev), do: Process.cancel_timer(prev)

    case conn.token_expires_at do
      %DateTime{} = exp ->
        ref = Process.send_after(self(), :token_expired, delay_ms(exp))
        {Map.put(state, :token_timer, ref), ref}

      _ ->
        {Map.put(state, :token_timer, nil), nil}
    end
  end

  @doc """
  连接中 token 到期：向本设备下发 `CMD_KICK`（`KICK_REASON_TOKEN_EXPIRED`）。
  """
  @spec kick_expired!(ConnectionState.t()) :: :ok
  def kick_expired!(%ConnectionState{context: ctx}) when not is_nil(ctx) do
    Kick.kick_device(ctx.app_key, ctx.user_id, ctx.device_id,
      reason: "token_expired",
      reason_code: KickReason.value(:KICK_REASON_TOKEN_EXPIRED),
      trace_id: ctx.trace_id
    )
  end

  def kick_expired!(_), do: :ok
end
