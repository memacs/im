defmodule IM.Telemetry.Outbound do
  @moduledoc """
  出站队列深度 / 等待 / 老化指标。
  """

  alias IM.Telemetry.Tags

  @doc """
  按优先级带采样队列深度（last_value，近似最近连接）。

  ## 示例

      IM.Telemetry.Outbound.depth(%{high: 1, normal: 2, low: 0})
  """
  @spec depth(%{high: non_neg_integer(), normal: non_neg_integer(), low: non_neg_integer()}) ::
          :ok
  def depth(%{high: h, normal: n, low: l}) do
    host = Tags.host()

    Enum.each([high: h, normal: n, low: l], fn {priority, depth} ->
      :telemetry.execute(
        [:im, :outbound, :depth],
        %{depth: depth},
        %{priority: priority, host: host}
      )
    end)
  end

  @doc """
  入队→写出等待。

  ## 示例

      IM.Telemetry.Outbound.wait_ms(12, :normal)
  """
  @spec wait_ms(non_neg_integer(), atom()) :: :ok
  def wait_ms(wait_ms, priority) when is_integer(wait_ms) and wait_ms >= 0 do
    :telemetry.execute(
      [:im, :outbound, :wait],
      %{duration: System.convert_time_unit(wait_ms, :millisecond, :native)},
      %{priority: priority, host: Tags.host()}
    )
  end

  @doc """
  老化升档。

  ## 示例

      IM.Telemetry.Outbound.aged(:low, :normal)
      IM.Telemetry.Outbound.aged(:low, :high, 3)
  """
  @spec aged(atom(), atom(), pos_integer()) :: :ok
  def aged(from, to, count \\ 1)
      when is_atom(from) and is_atom(to) and is_integer(count) and count > 0 do
    :telemetry.execute(
      [:im, :outbound, :aged],
      %{count: count},
      %{from: from, to: to, host: Tags.host()}
    )
  end
end
