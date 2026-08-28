defmodule IM.EventBus.AppEvents do
  @moduledoc """
  应用通道旁路：异步写入 `im.app_events`（经 `IM.EventBus` Facade）。

  失败不影响 ACK / PUSH 主路径。
  """

  alias IM.Domain.MessageContext
  alias IM.EventBus
  alias Pb.Im.Protocol.ChannelPublish

  @doc """
  客户端上行事件。

  ## 示例

      :ok = IM.EventBus.AppEvents.publish_up(req, ctx, "ev1")
  """
  @spec publish_up(ChannelPublish.t(), MessageContext.t(), String.t()) :: :ok
  def publish_up(%ChannelPublish{} = req, %MessageContext{} = ctx, event_id)
      when is_binary(event_id) do
    EventBus.publish(
      :app_events,
      %{
        event_id: event_id,
        timestamp: System.system_time(:millisecond),
        app_key: ctx.app_key,
        trace_id: ctx.trace_id,
        channel_id: req.channel_id,
        direction: :APP_EVENT_UP,
        user_id: ctx.user_id,
        device_id: ctx.device_id,
        content_type: req.content_type,
        payload: req.payload,
        client_event_id: req.client_event_id
      },
      partition_key: "#{ctx.app_key}:#{req.channel_id}"
    )
  end

  @doc """
  后端下行广播对应的聚合事件（每波 1 条）。

  ## 示例

      :ok = IM.EventBus.AppEvents.publish_down("demo", "fleet:alert", "ev1", %{}, "ops")
  """
  @spec publish_down(String.t(), String.t(), String.t(), map(), String.t()) :: :ok
  def publish_down(app_key, channel_id, event_id, attrs, caller_service)
      when is_binary(app_key) and is_binary(channel_id) and is_binary(event_id) do
    EventBus.publish(
      :app_events,
      %{
        event_id: event_id,
        timestamp: System.system_time(:millisecond),
        app_key: app_key,
        trace_id: Map.get(attrs, :trace_id, ""),
        channel_id: channel_id,
        direction: :APP_EVENT_DOWN,
        caller_service: caller_service,
        content_type: Map.get(attrs, :content_type, ""),
        payload: Map.get(attrs, :payload, <<>>)
      },
      partition_key: "#{app_key}:#{channel_id}"
    )
  end
end
