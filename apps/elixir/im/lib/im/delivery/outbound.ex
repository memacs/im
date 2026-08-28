defmodule IM.Delivery.Outbound do
  @moduledoc """
  出站优先级排序（P3-09）：同批按 priority 高→低，同级按 inbox_seq。

  批内排序见 `FanoutBatcher`；每连接调度见 `IM.Delivery.OutboundQueue`（挂在 PacketTransport）。
  """

  @doc """
  排序待推送项。每项 `%{priority: atom | integer, inbox_seq: integer, ...}`。

  ## 示例

      IM.Delivery.Outbound.sort_by_priority([%{priority: :low, inbox_seq: 2}, %{priority: :high, inbox_seq: 1}])
  """
  @spec sort_by_priority([map()]) :: [map()]
  def sort_by_priority(items) when is_list(items) do
    Enum.sort_by(items, fn item ->
      {-priority_rank(Map.get(item, :priority, 0)), Map.get(item, :inbox_seq, 0)}
    end)
  end

  defp priority_rank(:high), do: 2
  defp priority_rank(:MSG_PRIORITY_HIGH), do: 2
  defp priority_rank(1), do: 2
  defp priority_rank(:normal), do: 1
  defp priority_rank(:MSG_PRIORITY_NORMAL), do: 1
  defp priority_rank(0), do: 1
  defp priority_rank(:low), do: 0
  defp priority_rank(:MSG_PRIORITY_LOW), do: 0
  defp priority_rank(2), do: 0
  defp priority_rank(_), do: 1
end
