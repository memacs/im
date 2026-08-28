defmodule IM.EventBus.Upstream do
  @moduledoc """
  上行旁路：`im.upstream` 事件构造（含完整 `Packet.payload` 字节）。

  对齐 `docs/design/kafka-event-bus.md` §2.3：默认在业务校验通过后写入（`:accepted`）。
  """

  alias IM.Domain.MessageContext
  alias IM.EventBus
  alias Pb.Im.Protocol.{CmdType, MsgSendReq}

  @cmd_msg_send CmdType.value(:CMD_MSG_SEND)

  @doc """
  `CMD_MSG_SEND` 受理成功后发布上行事件。

  `opts` 可传 WS 原始字段：`payload`（`Packet.payload`）、`cmd`、`route_key`。
  REST/内部入口无原始 Packet 时，自动 encode `MsgSendReq{message}`。

  ## 示例

      :ok = IM.EventBus.Upstream.publish_message_send(msg, ctx, persisted, cmd: 100, payload: bin)
  """
  @spec publish_message_send(struct(), MessageContext.t(), map(), keyword()) :: :ok
  def publish_message_send(msg, %MessageContext{} = ctx, persisted, opts \\ []) do
    message = Map.fetch!(persisted, :message)

    EventBus.publish(
      :upstream,
      %{
        event_id: message.msg_id,
        msg_id: message.msg_id,
        conv_id: message.conv_id,
        chat_type: Map.get(msg, :chat_type),
        app_key: ctx.app_key,
        trace_id: ctx.trace_id,
        source: map_source(ctx.source),
        ingress: map_ingress(ctx.source),
        cmd: Keyword.get(opts, :cmd, @cmd_msg_send),
        user_id: ctx.user_id,
        from: ctx.user_id,
        device_id: ctx.device_id,
        route_key: Keyword.get(opts, :route_key, route_key(message, msg)),
        payload: Keyword.get(opts, :payload) || encode_payload(msg),
        duplicate?: Map.get(persisted, :duplicate?, false),
        timestamp: System.system_time(:millisecond)
      },
      write_kafka: Map.get(ctx, :write_kafka, true) != false
    )
  end

  @doc false
  @spec encode_payload(struct()) :: binary()
  def encode_payload(msg) do
    %MsgSendReq{message: msg} |> MsgSendReq.encode()
  end

  defp route_key(message, msg) do
    cid = Map.get(message, :conv_id)

    cond do
      is_binary(cid) and cid != "" -> cid
      is_binary(Map.get(msg, :conv_id)) and msg.conv_id != "" -> msg.conv_id
      is_binary(Map.get(msg, :to)) -> msg.to
      true -> ""
    end
  end

  defp map_source(:websocket), do: :EVENT_SOURCE_WEBSOCKET
  defp map_source(:http_client), do: :EVENT_SOURCE_HTTP
  defp map_source(:http_internal), do: :EVENT_SOURCE_INTERNAL
  defp map_source(:kafka), do: :EVENT_SOURCE_KAFKA
  defp map_source(:system), do: :EVENT_SOURCE_INTERNAL
  defp map_source(_), do: :EVENT_SOURCE_UNSPECIFIED

  defp map_ingress(:websocket), do: :INGRESS_WS
  defp map_ingress(:http_client), do: :INGRESS_REST
  defp map_ingress(:http_internal), do: :INGRESS_INTERNAL
  defp map_ingress(:kafka), do: :INGRESS_INTERNAL
  defp map_ingress(:system), do: :INGRESS_INTERNAL
  defp map_ingress(_), do: :INGRESS_UNSPECIFIED
end
