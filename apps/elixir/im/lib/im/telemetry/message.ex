defmodule IM.Telemetry.Message do
  @moduledoc """
  发消息 ACK 阶段延迟（DD-028 §2.4）：统一事件 `[:im, :ack, :latency]`。
  """

  alias IM.Telemetry.Tags

  @doc """
  SERVER_RECEIVED 之前耗时。

  ## 示例

      IM.Telemetry.Message.send_to_server_ack(start, :MSG_TEXT)
  """
  @spec send_to_server_ack(integer(), term(), term()) :: :ok
  def send_to_server_ack(start_native, msg_type, chat_type \\ :unknown) do
    ack_latency(:send_to_server_ack, start_native, msg_type, chat_type)
  end

  @doc """
  首次 PUSH 扇出耗时。

  ## 示例

      IM.Telemetry.Message.send_to_push(start, :MSG_TEXT)
  """
  @spec send_to_push(integer(), term(), term()) :: :ok
  def send_to_push(start_native, msg_type, chat_type \\ :unknown) do
    ack_latency(:send_to_push, start_native, msg_type, chat_type)
  end

  @doc """
  通用 ACK 阶段延迟（monotonic start）。

  ## 示例

      IM.Telemetry.Message.ack_latency(:heartbeat_rtt, start, :none, :unknown)
  """
  @spec ack_latency(atom(), integer(), term(), term()) :: :ok
  def ack_latency(stage, start_native, msg_type, chat_type)
      when is_atom(stage) and is_integer(start_native) do
    emit(stage, System.monotonic_time() - start_native, msg_type, chat_type)
  end

  @doc """
  以毫秒墙钟时长上报 ACK 阶段（如 `send_to_client_ack`）。

  ## 示例

      IM.Telemetry.Message.ack_latency_ms(:send_to_client_ack, 120, :MSG_TEXT, :CHAT_PRIVATE)
  """
  @spec ack_latency_ms(atom(), non_neg_integer(), term(), term()) :: :ok
  def ack_latency_ms(stage, duration_ms, msg_type, chat_type)
      when is_atom(stage) and is_integer(duration_ms) and duration_ms >= 0 do
    native = System.convert_time_unit(duration_ms, :millisecond, :native)
    emit(stage, native, msg_type, chat_type)
  end

  defp emit(stage, duration_native, msg_type, chat_type) do
    :telemetry.execute(
      [:im, :ack, :latency],
      %{duration: duration_native},
      %{
        stage: stage,
        chat_type: Tags.msg_type_name(chat_type),
        host: Tags.host(),
        msg_type: Tags.msg_type_name(msg_type)
      }
    )
  end
end
