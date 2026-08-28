defmodule IM.WebSocket.Commands.MsgSend do
  @moduledoc "`CMD_MSG_SEND` 薄适配。"

  alias IM.Cluster.GroupPusher
  alias IM.Cluster.Router, as: ClusterRouter
  alias IM.Delivery.Router, as: DeliveryRouter
  alias IM.Domain.Error
  alias IM.EventBus.Downstream
  alias IM.Protocol.{Codec, Push, Reply}
  alias IM.Room.PubSub, as: RoomPubSub
  alias IM.Services.Message
  alias IM.WebSocket.ConnectionState
  alias Pb.Im.Protocol.{CmdType, MsgSendReq, Packet}

  @doc false
  def handle(%Packet{} = packet, %ConnectionState{context: ctx} = state) when not is_nil(ctx) do
    with {:ok, %MsgSendReq{message: msg}} <- Codec.decode_payload(packet, MsgSendReq),
         route_key = resolve_route_key(packet, msg),
         {:ok, result} <-
           ClusterRouter.call(route_key, Message, :send, [msg, ctx, [cid: packet.cid]]),
         {:ok, ack_packet} <- Reply.ok(packet, :CMD_MSG_ACK_DOWN, result.ack),
         {:ok, ack_bin} <- Codec.encode(ack_packet) do
      unless result.duplicate? do
        push_to_recipients(result, ctx.app_key, packet.trace_id)
      end

      {:reply, ack_bin, ConnectionState.touch(state)}
    else
      {:error, %Error{} = err} ->
        err = %{err | ref_cmd: CmdType.value(:CMD_MSG_SEND)}

        case Reply.error(packet, err) do
          {:ok, out} ->
            {:ok, bin} = Codec.encode(out)
            {:reply, bin, ConnectionState.touch(state)}

          _ ->
            {:noreply, state}
        end

      {:error, reason} ->
        err = Error.new(:internal_error, "cluster forward: #{inspect(reason)}")
        err = %{err | ref_cmd: CmdType.value(:CMD_MSG_SEND)}

        case Reply.error(packet, err) do
          {:ok, out} ->
            {:ok, bin} = Codec.encode(out)
            {:reply, bin, ConnectionState.touch(state)}

          _ ->
            {:noreply, state}
        end
    end
  end

  def handle(_packet, state), do: {:stop, ConnectionState.closing(state)}

  defp resolve_route_key(%Packet{route_key: rk}, _msg) when is_binary(rk) and rk != "", do: rk
  defp resolve_route_key(_packet, %{conv_id: cid}) when is_binary(cid) and cid != "", do: cid
  defp resolve_route_key(_packet, %{to: to}) when is_binary(to), do: to
  defp resolve_route_key(_, _), do: ""

  @doc false
  def push_to_recipients(result, app_key, trace_id) do
    message = %{result.message | inbox_seq: 0}
    recipients = result.recipient_user_ids || List.wrap(result.peer_user_id)

    case Push.build(:CMD_MSG_PUSH, message,
           trace_id: trace_id,
           route_key: message.conv_id,
           cid: message.client_msg_id || ""
         ) do
      {:ok, push_packet} ->
        case Codec.encode(push_packet) do
          {:ok, bin} ->
            case message.chat_type do
              :CHAT_ROOM ->
                RoomPubSub.broadcast(app_key, message.to, bin, %{
                  exclude_device_id: result.sender_device_id,
                  sender_user_id: result.sender_user_id,
                  target_users: message.target_users || []
                })

              :CHAT_GROUP ->
                exclude = %{result.sender_user_id => result.sender_device_id}

                _ =
                  GroupPusher.push(app_key, recipients, bin,
                    exclude: exclude,
                    msg_id: message.msg_id,
                    conv_id: message.conv_id
                  )

              _ ->
                exclude = %{result.sender_user_id => result.sender_device_id}

                Enum.each(recipients, fn uid ->
                  excl = Map.get(exclude, uid)

                  _ =
                    DeliveryRouter.push_binary(app_key, uid, bin,
                      exclude_device_id: excl,
                      msg_id: message.msg_id,
                      conv_id: message.conv_id
                    )
                end)
            end

            # 旁路下行 1 条（大群 aggregated）
            _ =
              Downstream.publish_push(
                %{
                  msg_id: message.msg_id,
                  conv_id: message.conv_id,
                  chat_type: message.chat_type,
                  to: message.to,
                  from: message.from,
                  app_key: app_key
                },
                recipients,
                %{from_user_id: result.sender_user_id}
              )

          _ ->
            :ok
        end

      _ ->
        :ok
    end
  end
end
