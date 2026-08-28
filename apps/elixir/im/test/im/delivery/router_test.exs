defmodule IM.Delivery.RouterTest do
  use IM.DataCase, async: false

  alias IM.AuthFixtures
  alias IM.Delivery.{MobilePush, Router}
  alias IM.Stores.UserDeviceStore

  test "push_binary 无在线设备且有 push_token 时入队 MobilePush" do
    %{app_key: app, user_id: user} = AuthFixtures.create_user!()

    {:ok, _} =
      UserDeviceStore.upsert(%{
        app_key: app,
        user_id: user,
        device_id: "d-off",
        platform: "ios",
        push_token: "tok-router"
      })

    _ = UserDeviceStore.set_online(app, user, "d-off", false)
    _ = MobilePush.drain()

    assert :ok =
             Router.push_binary(app, user, <<"packet">>, msg_id: "m1", conv_id: "p:a:b")

    items = MobilePush.drain()
    assert length(items) == 1
    assert hd(items).push_token == "tok-router"
  end
end
