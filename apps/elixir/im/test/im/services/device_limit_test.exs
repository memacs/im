defmodule IM.Services.DeviceLimitTest do
  use ExUnit.Case, async: false

  alias IM.Connection.Registry
  alias IM.Domain.Error
  alias IM.Services.DeviceLimit

  setup do
    previous = Application.get_env(:im, :device_limit)

    Application.put_env(:im, :device_limit, %{
      max_per_platform: 1,
      policy: :reject
    })

    on_exit(fn ->
      if previous,
        do: Application.put_env(:im, :device_limit, previous),
        else: Application.delete_env(:im, :device_limit)
    end)

    n = System.unique_integer([:positive])
    %{app: "dl_app_#{n}", user: "dl_u_#{n}"}
  end

  test "超限 reject 返回 device_limit_exceeded", %{app: app, user: user} do
    :ok = Registry.register(app, user, "d1", "ios")

    assert {:error, %Error{code: :device_limit_exceeded}} =
             DeviceLimit.enforce(app, user, "d2", "ios")
  end

  test "同 device_id 重连不超限", %{app: app, user: user} do
    :ok = Registry.register(app, user, "d1", "ios")
    assert {:ok, %{kick_oldest: nil}} = DeviceLimit.enforce(app, user, "d1", "ios")
  end
end
