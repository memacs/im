defmodule IM.Delivery.Router do
  @moduledoc """
  下行扇出：优先经 `IM.UserTracker` 定位连接 pid（可跨节点 `send/2`），
  回退本节点 `Connection.Registry`。
  """

  require IM.Log

  alias IM.Connection.Registry
  alias IM.Delivery.{MobilePush, OutboundQueue}
  alias IM.Domain.Error
  alias IM.Protocol.{Codec, Push}
  alias IM.Telemetry.Cluster, as: ClusterTelemetry
  alias IM.Telemetry.Delivery, as: DeliveryTelemetry
  alias IM.Telemetry.Message, as: MsgTelemetry
  alias IM.UserTracker
  alias Pb.Im.Protocol.{ChatMessage, Packet}

  @doc """
  推送 ChatMessage 给用户的在线设备，可排除某 device_id。

  ## 示例

      IM.Delivery.Router.push_message(msg, app_key, user_id, exclude_device_id: "d1", trace_id: "t")
  """
  @spec push_message(ChatMessage.t(), String.t(), String.t(), keyword()) :: :ok
  def push_message(%ChatMessage{} = message, app_key, user_id, opts \\ []) do
    start = System.monotonic_time()
    exclude = Keyword.get(opts, :exclude_device_id)
    trace_id = Keyword.get(opts, :trace_id, "")

    with {:ok, packet} <-
           Push.build(:CMD_MSG_PUSH, message,
             trace_id: trace_id,
             route_key: message.conv_id,
             cid: message.client_msg_id || ""
           ),
         {:ok, bin} <- Codec.encode(packet) do
      meta = push_meta(message)
      recipients = deliver_bin(app_key, user_id, bin, exclude, meta)
      maybe_enqueue_mobile_push(app_key, user_id, bin, recipients, opts)

      DeliveryTelemetry.stop(start,
        recipient_count: recipients,
        chat_type: message.chat_type,
        fanout_mode: :direct,
        msg_type: message.msg_type
      )

      MsgTelemetry.send_to_push(start, message.msg_type || :none, message.chat_type || :unknown)
      :ok
    else
      {:error, reason} ->
        IM.Log.error(:push_failed,
          reason: inspect(reason),
          app_key: app_key,
          user_id: user_id
        )

        :ok
    end
  end

  @doc """
  向用户各在线设备推送任意已构造 Packet（如 ACK_DOWN）。

  ## 示例

      IM.Delivery.Router.push_packet(packet, app_key, user_id)
  """
  @spec push_packet(Packet.t(), String.t(), String.t(), keyword()) :: :ok | {:error, Error.t()}
  def push_packet(%Packet{} = packet, app_key, user_id, opts \\ []) do
    exclude = Keyword.get(opts, :exclude_device_id)

    case Codec.encode(packet) do
      {:ok, bin} ->
        _ = deliver_bin(app_key, user_id, bin, exclude, Keyword.get(opts, :push_meta, %{}))
        :ok

      {:error, reason} = err ->
        IM.Log.error(:push_failed,
          reason: inspect(reason),
          app_key: app_key,
          user_id: user_id
        )

        err
    end
  end

  @doc """
  推送已编码的 Packet 二进制（P5-04：群发预编码一次后多用户复用）。

  ## 示例

      IM.Delivery.Router.push_binary(app_key, user_id, bin, exclude_device_id: "d1", priority: :high)
  """
  @spec push_binary(String.t(), String.t(), binary(), keyword()) :: :ok
  def push_binary(app_key, user_id, bin, opts \\ []) when is_binary(bin) do
    start = System.monotonic_time()

    meta = %{
      priority: Keyword.get(opts, :priority, :normal),
      inbox_seq: Keyword.get(opts, :inbox_seq, 0)
    }

    recipients = deliver_bin(app_key, user_id, bin, Keyword.get(opts, :exclude_device_id), meta)
    maybe_enqueue_mobile_push(app_key, user_id, bin, recipients, opts)

    DeliveryTelemetry.stop(start,
      recipient_count: recipients,
      chat_type: Keyword.get(opts, :chat_type, :unknown),
      fanout_mode: Keyword.get(opts, :fanout_mode, :direct),
      msg_type: Keyword.get(opts, :msg_type, :none)
    )

    :ok
  end

  @doc false
  @spec deliver(map() | struct(), map()) :: :ok | {:error, Error.t()}
  def deliver(%ChatMessage{} = message, %{app_key: app, user_id: user} = opts) do
    push_message(message, app, user, Map.to_list(opts))
  end

  def deliver(_message, _ctx),
    do: {:error, Error.new(:msg_invalid, "unsupported deliver payload")}

  defp push_meta(%ChatMessage{} = message) do
    %{
      priority: OutboundQueue.normalize_priority(message.priority),
      inbox_seq: message.inbox_seq || 0
    }
  end

  defp deliver_bin(app_key, user_id, bin, exclude, meta) do
    msg = {:im_push, bin, meta || %{}}
    self_node = node()

    case UserTracker.list_devices(app_key, user_id) do
      [_ | _] = devices ->
        Enum.reduce(devices, 0, fn %{pid: pid, device_id: device_id}, acc ->
          if is_nil(exclude) or device_id != exclude do
            if is_pid(pid) and node(pid) != self_node and self_node != :nonode@nohost do
              ClusterTelemetry.dispatch(1)
            end

            send(pid, msg)
            acc + 1
          else
            acc
          end
        end)

      [] ->
        Registry.list_user_devices(app_key, user_id)
        |> Enum.reduce(0, fn reg_meta, acc ->
          device_id = reg_meta[:device_id]

          if is_nil(exclude) or device_id != exclude do
            _ = Registry.send_device(app_key, user_id, device_id, msg)
            acc + 1
          else
            acc
          end
        end)
    end
  end

  defp maybe_enqueue_mobile_push(_app_key, _user_id, _bin, recipients, _opts)
       when is_integer(recipients) and recipients > 0,
       do: :ok

  defp maybe_enqueue_mobile_push(app_key, user_id, bin, _recipients, opts) do
    MobilePush.maybe_enqueue(app_key, user_id, bin,
      online?: false,
      msg_id: Keyword.get(opts, :msg_id),
      conv_id: Keyword.get(opts, :conv_id)
    )
  end
end
