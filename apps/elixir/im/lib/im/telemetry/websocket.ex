defmodule IM.Telemetry.Websocket do
  @moduledoc """
  WebSocket 包计数 / Handler 耗时（对齐 DD-028 §2.3）。

  事件：`[:im, :packet, :received|:sent|:error]`、`[:im, :handler, :stop]`。
  """

  alias IM.Telemetry.Tags

  @doc """
  上行收包（解码成功后）。

  ## 示例

      IM.Telemetry.Websocket.frame_in(128, 100)
  """
  @spec frame_in(non_neg_integer(), term(), term()) :: :ok
  def frame_in(bytes, cmd, msg_type \\ :none) do
    :telemetry.execute(
      [:im, :packet, :received],
      %{bytes: bytes, count: 1},
      Tags.packet_meta(cmd, :up, msg_type)
    )
  end

  @doc """
  下行发包（编码前/写出前）。

  ## 示例

      IM.Telemetry.Websocket.frame_out(64, 101)
  """
  @spec frame_out(non_neg_integer(), term(), term()) :: :ok
  def frame_out(bytes, cmd, msg_type \\ :none) do
    :telemetry.execute(
      [:im, :packet, :sent],
      %{bytes: bytes, count: 1},
      Tags.packet_meta(cmd, :down, msg_type)
    )
  end

  @doc """
  `CMD_ERROR` 计数。

  ## 示例

      IM.Telemetry.Websocket.packet_error(2004, "CMD_MSG_SEND")
  """
  @spec packet_error(term(), term()) :: :ok
  def packet_error(code, ref_cmd) do
    :telemetry.execute(
      [:im, :packet, :error],
      %{count: 1},
      %{
        code: to_string(code),
        ref_cmd: Tags.cmd_name(ref_cmd),
        host: Tags.host()
      }
    )
  end

  @doc """
  Handler 耗时（native time）。

  ## 示例

      start = System.monotonic_time()
      IM.Telemetry.Websocket.handler_stop(start, 1, :ok)
  """
  @spec handler_stop(integer(), term(), atom(), term()) :: :ok
  def handler_stop(start_native, cmd, result \\ :ok, msg_type \\ :none) do
    duration = System.monotonic_time() - start_native

    :telemetry.execute(
      [:im, :handler, :stop],
      %{duration: duration},
      %{
        cmd: Tags.cmd_name(cmd),
        result: result,
        direction: :up,
        msg_type: Tags.msg_type_name(msg_type),
        host: Tags.host()
      }
    )
  end
end
