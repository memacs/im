defmodule IM.EventBus.Session do
  @moduledoc "会话旁路：login / logout / heartbeat（P9-03b 采样）。"

  alias IM.Domain.MessageContext
  alias IM.EventBus

  @doc """
  登录事件。

  ## 示例

      :ok = IM.EventBus.Session.login(ctx)
  """
  @spec login(MessageContext.t()) :: :ok
  def login(%MessageContext{} = ctx) do
    EventBus.publish(
      :session,
      %{
        type: "login",
        app_key: ctx.app_key,
        user_id: ctx.user_id,
        device_id: ctx.device_id,
        session_id: ctx.session_id,
        platform: ctx.platform,
        trace_id: ctx.trace_id
      },
      write_kafka: Map.get(ctx, :write_kafka, true) != false
    )
  end

  @doc "登出事件。"
  @spec logout(MessageContext.t(), term()) :: :ok
  def logout(%MessageContext{} = ctx, reason) do
    EventBus.publish(
      :session,
      %{
        type: "logout",
        app_key: ctx.app_key,
        user_id: ctx.user_id,
        device_id: ctx.device_id,
        reason: inspect(reason),
        trace_id: ctx.trace_id
      },
      write_kafka: Map.get(ctx, :write_kafka, true) != false
    )
  end

  @doc "心跳事件（可采样）。"
  @spec heartbeat(MessageContext.t()) :: :ok
  def heartbeat(%MessageContext{} = ctx) do
    if heartbeat_allowed?(ctx) do
      EventBus.publish(
        :session,
        %{
          type: "heartbeat",
          app_key: ctx.app_key,
          user_id: ctx.user_id,
          device_id: ctx.device_id,
          trace_id: ctx.trace_id
        },
        write_kafka: Map.get(ctx, :write_kafka, true) != false
      )
    end

    :ok
  end

  defp heartbeat_allowed?(ctx) do
    cfg = Application.get_env(:im, :event_bus_kafka, [])

    case Keyword.get(cfg, :session_heartbeat_mode, :sampled) do
      :off -> false
      :all -> true
      :sampled -> sampled?(ctx, cfg)
      _ -> false
    end
  end

  defp sampled?(ctx, cfg) do
    rate = Keyword.get(cfg, :session_heartbeat_sample_rate, 0.01)
    min_ms = Keyword.get(cfg, :session_heartbeat_min_interval_ms, 300_000)
    key = {ctx.app_key, ctx.user_id, ctx.device_id}
    now = System.monotonic_time(:millisecond)

    case :persistent_term.get({__MODULE__, :hb, key}, nil) do
      last when is_integer(last) and now - last < min_ms ->
        false

      _ ->
        if :rand.uniform() <= rate do
          :persistent_term.put({__MODULE__, :hb, key}, now)
          true
        else
          false
        end
    end
  end
end
