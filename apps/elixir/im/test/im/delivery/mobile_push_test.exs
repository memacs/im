defmodule IM.Delivery.MobilePushTest do
  use IM.DataCase, async: false

  alias IM.AuthFixtures
  alias IM.Delivery.MobilePush
  alias IM.Stores.UserDeviceStore

  test "离线且有 push_token 时入队" do
    %{app_key: app, user_id: user} = AuthFixtures.create_user!()

    {:ok, _} =
      UserDeviceStore.upsert(%{
        app_key: app,
        user_id: user,
        device_id: "d-push",
        platform: "ios",
        push_token: "tok-1"
      })

    _ = UserDeviceStore.set_online(app, user, "d-push", false)
    _ = MobilePush.drain()

    assert :ok = MobilePush.maybe_enqueue(app, user, <<"bin">>, online?: false)
    items = MobilePush.drain()
    assert length(items) == 1
    assert hd(items).push_token == "tok-1"
  end
end
