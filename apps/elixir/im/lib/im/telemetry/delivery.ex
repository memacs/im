defmodule IM.Telemetry.Delivery do
  @moduledoc """
  投递耗时与扇出规模（`im_delivery_duration_ms` / `im_push_recipients`）。
  """

  alias IM.Telemetry.Tags

  @doc """
  上报投递 span 与收件人数。

  ## 示例

      IM.Telemetry.Delivery.stop(start, recipient_count: 3, chat_type: :CHAT_PRIVATE)
  """
  @spec stop(integer(), keyword()) :: :ok
  def stop(start_native, opts \\ []) when is_integer(start_native) do
    chat_type = Keyword.get(opts, :chat_type, :unknown)
    fanout_mode = Keyword.get(opts, :fanout_mode, :direct)
    msg_type = Keyword.get(opts, :msg_type, :none)
    recipients = Keyword.get(opts, :recipient_count, 0)

    meta = %{
      chat_type: Tags.msg_type_name(chat_type),
      fanout_mode: Tags.msg_type_name(fanout_mode),
      host: Tags.host(),
      msg_type: Tags.msg_type_name(msg_type)
    }

    :telemetry.execute(
      [:im, :delivery, :stop],
      %{duration: System.monotonic_time() - start_native, recipients: recipients},
      meta
    )
  end
end
