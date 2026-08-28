defmodule IM.Channel.RateLimiter do
  @moduledoc """
  App Channel 上行限速：连接令牌桶 + Channel 聚合窗口。

  默认 1/s、burst 2；聚合默认 5000/s。见 `docs/design/app-channel.md` §7。
  """

  require IM.Log

  @table :im_channel_rate_limiter

  @doc """
  确保 ETS 表存在（Application 启动时调用）。

  ## 示例

      :ok = IM.Channel.RateLimiter.ensure_table()
  """
  @spec ensure_table() :: :ok
  def ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        _ = :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
        :ok

      _ ->
        :ok
    end
  end

  @doc "测试用：清空计数。"
  @spec reset() :: :ok
  def reset do
    ensure_table()
    :ets.delete_all_objects(@table)
    :ok
  end

  @doc """
  连接级令牌桶：通过返回 `:ok`，否则 `:rate_limited`。

  ## 示例

      :ok = IM.Channel.RateLimiter.allow_conn?("a", "u", "d")
  """
  @spec allow_conn?(String.t(), String.t(), String.t()) :: :ok | :rate_limited
  def allow_conn?(app_key, user_id, device_id)
      when is_binary(app_key) and is_binary(user_id) and is_binary(device_id) do
    ensure_table()
    rate = Application.get_env(:im, :channel_publish_rate_per_conn, 1)
    burst = Application.get_env(:im, :channel_publish_burst, 2)
    key = {:conn, app_key, user_id, device_id}
    now = System.monotonic_time(:millisecond)

    case token_bucket(key, rate, burst, now) do
      :rate_limited ->
        IM.Log.warning(:rate_limited,
          app_key: app_key,
          user_id: user_id,
          device_id: device_id,
          reason: "channel_conn"
        )

        :rate_limited

      :ok ->
        :ok
    end
  end

  @doc """
  Channel 聚合上限。

  ## 示例

      :ok = IM.Channel.RateLimiter.allow_channel_aggregate?("a", "fleet:alert")
  """
  @spec allow_channel_aggregate?(String.t(), String.t()) :: :ok | :rate_limited
  def allow_channel_aggregate?(app_key, channel_id)
      when is_binary(app_key) and is_binary(channel_id) do
    ensure_table()
    max = Application.get_env(:im, :channel_publish_aggregate_max, 5000)
    key = {:agg, app_key, channel_id}
    now = System.system_time(:second)

    case :ets.lookup(@table, key) do
      [{^key, {window, count}}] when window == now and count >= max ->
        :telemetry.execute([:im, :channel, :aggregate_drop], %{count: 1}, %{
          channel_id: channel_id
        })

        :rate_limited

      [{^key, {window, count}}] when window == now ->
        :ets.insert(@table, {key, {window, count + 1}})
        :ok

      _ ->
        :ets.insert(@table, {key, {now, 1}})
        :ok
    end
  end

  defp token_bucket(key, rate, burst, now) when rate > 0 and burst > 0 do
    case :ets.lookup(@table, key) do
      [{^key, {tokens, last}}] ->
        elapsed_s = max(now - last, 0) / 1000
        refilled = min(burst * 1.0, tokens + elapsed_s * rate)

        if refilled >= 1.0 do
          :ets.insert(@table, {key, {refilled - 1.0, now}})
          :ok
        else
          :ets.insert(@table, {key, {refilled, now}})
          :rate_limited
        end

      [] ->
        # 首次：burst-1 剩余
        :ets.insert(@table, {key, {burst * 1.0 - 1.0, now}})
        :ok
    end
  end
end
