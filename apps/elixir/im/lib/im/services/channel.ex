defmodule IM.Services.Channel do
  @moduledoc """
  应用通道业务：订阅/取消、客户端上行、后端下行广播。

  设计见 `docs/design/app-channel.md`；实现见 `docs/implementation/elixir/app-channel.md`。
  """

  require IM.Log

  alias IM.Channel.{ACL, RateLimiter}
  alias IM.Delivery.ChannelRouter
  alias IM.Domain.{Error, MessageContext}
  alias IM.EventBus.AppEvents
  alias IM.Protocol.{Codec, Push}

  alias Pb.Im.Protocol.{
    ChannelPublish,
    ChannelPublishAck,
    ChannelPush,
    ChannelSubscribeError,
    ChannelSubscribeResp,
    ChannelUnsubscribeResp
  }

  @doc """
  ACL 校验订阅列表；可选在当前进程执行 PubSub.subscribe。

  ## Options

  - `:pubsub` — `true` 时对本进程 subscribe（WS）；REST 传 `false`

  ## 示例

      {:ok, %ChannelSubscribeResp{}} = IM.Services.Channel.subscribe(["fleet:alert"], ctx)
  """
  @spec subscribe([String.t()], MessageContext.t(), keyword()) ::
          {:ok, ChannelSubscribeResp.t()} | {:error, Error.t()}
  def subscribe(channel_ids, %MessageContext{} = ctx, opts \\ []) when is_list(channel_ids) do
    do_pubsub? = Keyword.get(opts, :pubsub, false)

    {subscribed, failed} =
      Enum.reduce(channel_ids, {[], []}, fn id, {ok_acc, fail_acc} ->
        case ACL.allow_subscribe?(ctx.app_key, id, ctx.user_id) do
          :ok ->
            if do_pubsub?, do: ChannelRouter.subscribe(ctx.app_key, id)
            {[id | ok_acc], fail_acc}

          {:error, %Error{} = err} ->
            IM.Log.warning(:channel_subscribe_denied,
              app_key: ctx.app_key,
              user_id: ctx.user_id,
              channel_id: id,
              reason: err.msg || Atom.to_string(err.code)
            )

            fail = %ChannelSubscribeError{
              channel_id: to_string(id),
              code: IM.Protocol.ErrorCodes.to_int(err.code),
              msg: err.msg || ""
            }

            {ok_acc, [fail | fail_acc]}
        end
      end)

    {:ok,
     %ChannelSubscribeResp{
       subscribed: Enum.reverse(subscribed),
       failed: Enum.reverse(failed)
     }}
  end

  @doc """
  取消订阅。

  ## 示例

      {:ok, %ChannelUnsubscribeResp{}} = IM.Services.Channel.unsubscribe(["fleet:alert"], ctx)
  """
  @spec unsubscribe([String.t()], MessageContext.t(), keyword()) ::
          {:ok, ChannelUnsubscribeResp.t()} | {:error, Error.t()}
  def unsubscribe(channel_ids, %MessageContext{} = ctx, opts \\ []) when is_list(channel_ids) do
    do_pubsub? = Keyword.get(opts, :pubsub, false)

    unsubscribed =
      Enum.reduce(channel_ids, [], fn id, acc ->
        case ACL.validate_channel_id(id) do
          :ok ->
            if do_pubsub?, do: ChannelRouter.unsubscribe(ctx.app_key, id)
            [id | acc]

          {:error, _} ->
            acc
        end
      end)

    {:ok, %ChannelUnsubscribeResp{unsubscribed: Enum.reverse(unsubscribed)}}
  end

  @doc """
  客户端上行。超限返回 `:drop_silent`。

  ## 示例

      {:ok, %ChannelPublishAck{}} = IM.Services.Channel.publish_up(req, ctx)
  """
  @spec publish_up(ChannelPublish.t(), MessageContext.t()) ::
          {:ok, ChannelPublishAck.t()} | :drop_silent | {:error, Error.t()}
  def publish_up(%ChannelPublish{} = req, %MessageContext{} = ctx) do
    with :ok <- ACL.allow_client_publish?(ctx.app_key, req.channel_id, ctx.user_id),
         :ok <- RateLimiter.allow_conn?(ctx.app_key, ctx.user_id, ctx.device_id),
         :ok <- RateLimiter.allow_channel_aggregate?(ctx.app_key, req.channel_id) do
      event_id = Ecto.UUID.generate()
      _ = AppEvents.publish_up(req, ctx, event_id)

      {:ok,
       %ChannelPublishAck{
         channel_id: req.channel_id,
         event_id: event_id,
         accepted: true
       }}
    else
      :rate_limited ->
        IM.Log.warning(:channel_publish_dropped,
          reason: "rate_limited",
          app_key: ctx.app_key,
          user_id: ctx.user_id,
          channel_id: req.channel_id
        )

        :drop_silent

      {:error, %Error{}} = err ->
        err
    end
  end

  @doc """
  后端下行广播：编码一次 + PubSub + 旁路 DOWN 事件。

  ## 示例

      {:ok, %{event_id: id}} = IM.Services.Channel.publish_down("demo", "fleet:alert", attrs, "ops")
  """
  @spec publish_down(String.t(), String.t(), map(), String.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def publish_down(app_key, channel_id, attrs, caller_service)
      when is_binary(app_key) and is_binary(channel_id) and is_binary(caller_service) do
    with :ok <- ACL.allow_internal_publish?(app_key, channel_id, caller_service),
         event_id = Ecto.UUID.generate(),
         content_type = Map.get(attrs, :content_type) || Map.get(attrs, "content_type") || "",
         payload = normalize_payload(Map.get(attrs, :payload) || Map.get(attrs, "payload")),
         push = %ChannelPush{
           channel_id: channel_id,
           content_type: content_type,
           payload: payload,
           event_id: event_id,
           server_time: System.system_time(:millisecond),
           caller_service: caller_service
         },
         {:ok, packet} <-
           Push.build(:CMD_CHANNEL_PUSH, push,
             trace_id: Map.get(attrs, :trace_id) || Map.get(attrs, "trace_id") || "",
             route_key: channel_id
           ),
         {:ok, bin} <- Codec.encode(packet),
         :ok <- ChannelRouter.broadcast(app_key, channel_id, bin) do
      _ =
        AppEvents.publish_down(
          app_key,
          channel_id,
          event_id,
          %{
            content_type: content_type,
            payload: payload,
            trace_id: packet.trace_id
          },
          caller_service
        )

      {:ok, %{event_id: event_id, channel_id: channel_id}}
    end
  end

  defp normalize_payload(nil), do: <<>>
  defp normalize_payload(bin) when is_binary(bin), do: bin
  defp normalize_payload(other), do: Jason.encode!(other)
end
