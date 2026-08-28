defmodule IM.UserTrackerTest do
  use ExUnit.Case, async: false

  alias IM.UserTracker

  test "track 后 list_devices 可见本进程" do
    app = "app_trk"
    user = "u_#{System.unique_integer([:positive])}"
    device = "d1"

    assert :ok = UserTracker.track(app, user, device, %{platform: "ios"})
    # Tracker 异步复制，短暂等待本节点可见
    assert wait_until(fn ->
             Enum.any?(UserTracker.list_devices(app, user), &(&1.device_id == device and &1.pid == self()))
           end)
  end

  defp wait_until(fun, attempts \\ 20) do
    cond do
      fun.() -> true
      attempts <= 0 -> false
      true ->
        Process.sleep(20)
        wait_until(fun, attempts - 1)
    end
  end
end
