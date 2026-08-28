defmodule IM.Delivery.ChannelRouter do
  @moduledoc """
  App Channel PubSub 扇出：topic / subscribe / 预编码 broadcast。

  **不**使用 `GroupPusher` / 树状扇出。见 `docs/implementation/elixir/app-channel.md`。
  """

  @pubsub IM.PubSub

  @doc """
  PubSub topic：`channel:{app_key}:{channel_id}`。

  ## 示例

      "channel:demo:fleet:alert" = IM.Delivery.ChannelRouter.topic("demo", "fleet:alert")
  """
  @spec topic(String.t(), String.t()) :: String.t()
  def topic(app_key, channel_id), do: "channel:#{app_key}:#{channel_id}"

  @doc """
  当前进程订阅通道。

  ## 示例

      :ok = IM.Delivery.ChannelRouter.subscribe("demo", "fleet:alert")
  """
  @spec subscribe(String.t(), String.t()) :: :ok
  def subscribe(app_key, channel_id) do
    :ok = Phoenix.PubSub.subscribe(@pubsub, topic(app_key, channel_id))
  end

  @doc """
  取消订阅。

  ## 示例

      :ok = IM.Delivery.ChannelRouter.unsubscribe("demo", "fleet:alert")
  """
  @spec unsubscribe(String.t(), String.t()) :: :ok
  def unsubscribe(app_key, channel_id) do
    :ok = Phoenix.PubSub.unsubscribe(@pubsub, topic(app_key, channel_id))
  end

  @doc """
  广播已编码的 `CMD_CHANNEL_PUSH` 帧。

  ## 示例

      :ok = IM.Delivery.ChannelRouter.broadcast("demo", "fleet:alert", <<1, 2, 3>>)
  """
  @spec broadcast(String.t(), String.t(), binary()) :: :ok
  def broadcast(app_key, channel_id, packet_binary) when is_binary(packet_binary) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      topic(app_key, channel_id),
      {:channel_push, packet_binary}
    )
  end
end
