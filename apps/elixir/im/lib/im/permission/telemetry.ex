defmodule IM.Permission.Telemetry do
  @moduledoc "权限检查指标（DD-033 §6）。"

  @doc """
  上报一次权限检查。

  - `type`: `:block` | `:mute` | `:device_ban`
  - `result`: `:allow` | `:deny`
  - `layer`: `:l1` | `:l2` | `:pg`
  """
  @spec emit_check(atom(), atom(), atom()) :: :ok
  def emit_check(type, result, layer)
      when type in [:block, :mute, :device_ban] and result in [:allow, :deny] and
             layer in [:l1, :l2, :pg] do
    :telemetry.execute(
      [:im, :permission, :check],
      %{count: 1},
      %{type: type, result: result, layer: layer}
    )

    :ok
  end

  @doc "上报对账修复条数。"
  @spec emit_drift(atom(), non_neg_integer()) :: :ok
  def emit_drift(type, count)
      when type in [:block, :mute, :device_ban, :group_member, :friendship] and is_integer(count) do
    if count > 0 do
      :telemetry.execute(
        [:im, :permission, :cache_drift],
        %{count: count},
        %{type: type}
      )
    end

    :ok
  end
end
