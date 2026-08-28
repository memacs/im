defmodule IM.Telemetry.MsgBurn do
  @moduledoc """
  阅后即焚指标（burn-after-read §8）。
  """

  alias IM.Telemetry.Tags

  @doc """
  已读触发调度。

  ## 示例

      IM.Telemetry.MsgBurn.scheduled()
  """
  @spec scheduled() :: :ok
  def scheduled do
    :telemetry.execute(
      [:im, :msg_burn, :scheduled],
      %{count: 1},
      %{host: Tags.host()}
    )
  end

  @doc """
  实际销毁；`lag_ms` 为相对计划销毁时刻的延迟。

  ## 示例

      IM.Telemetry.MsgBurn.executed(120)
  """
  @spec executed(non_neg_integer()) :: :ok
  def executed(lag_ms) when is_integer(lag_ms) and lag_ms >= 0 do
    :telemetry.execute(
      [:im, :msg_burn, :executed],
      %{
        count: 1,
        lag: System.convert_time_unit(lag_ms, :millisecond, :native)
      },
      %{host: Tags.host()}
    )
  end
end
