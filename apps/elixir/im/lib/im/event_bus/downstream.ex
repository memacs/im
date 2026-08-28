defmodule IM.EventBus.Downstream do
  @moduledoc "下行旁路：扇出结束后写 1 条（P9-03b aggregated）。"

  alias IM.EventBus
  alias IM.EventBus.FanoutPolicy

  @doc """
  发布下行扇出摘要。大群/聊天室为 aggregated，不写全量 targets。

  ## 示例

      :ok = IM.EventBus.Downstream.publish_push(message, recipients, ctx_map)
  """
  @spec publish_push(map(), [String.t()], map()) :: :ok
  def publish_push(message, recipient_user_ids, meta \\ %{})
      when is_map(message) and is_list(recipient_user_ids) do
    {mode, _} = FanoutPolicy.resolve(message, recipient_user_ids)
    max = recipient_list_max(mode)

    {list, truncated?} = truncate(Enum.uniq(recipient_user_ids), max)

    EventBus.publish(:downstream, %{
      event_id: Map.get(message, :msg_id) || Map.get(message, "msg_id"),
      msg_id: Map.get(message, :msg_id) || Map.get(message, "msg_id"),
      app_key: first_str(meta, message, :app_key),
      trace_id: first_str(meta, message, :trace_id),
      cmd: Map.get(meta, :cmd) || Map.get(meta, "cmd") || 0,
      conv_id: Map.get(message, :conv_id),
      chat_type: Map.get(message, :chat_type),
      payload: Map.get(meta, :payload) || Map.get(meta, "payload") || <<>>,
      fanout: %{
        mode: mode,
        recipient_count: length(recipient_user_ids),
        audience: %{
          from_user_id: Map.get(meta, :from_user_id) || Map.get(message, :from),
          from_device_id: Map.get(meta, :from_device_id),
          recipient_user_ids: list,
          recipient_list_truncated: truncated?,
          recipient_list_max: max
        }
      }
    })
  end

  defp recipient_list_max(:group_aggregated) do
    cfg(:downstream_group_recipient_list_max, 500)
  end

  defp recipient_list_max(:room_aggregated) do
    cfg(:downstream_room_recipient_list_max, 2000)
  end

  defp recipient_list_max(_), do: :infinity

  defp truncate(list, :infinity), do: {list, false}

  defp truncate(list, max) when is_integer(max) do
    if length(list) > max do
      {Enum.take(list, max), true}
    else
      {list, false}
    end
  end

  defp cfg(key, default) do
    Application.get_env(:im, :event_bus_kafka, []) |> Keyword.get(key, default)
  end

  defp first_str(meta, message, key) do
    Map.get(meta, key) || Map.get(meta, to_string(key)) ||
      Map.get(message, key) || Map.get(message, to_string(key)) || ""
  end
end
