defmodule IM.Services.DeviceBanTest do
  use IM.DataCase, async: true

  alias IM.AuthFixtures
  alias IM.Services.{DeviceBan, Session}
  alias IM.Stores.UserDeviceStore

  test "封禁后登录失败；ACK 清除 pending" do
    %{app_key: app_key, user_id: user_id, password: password, device_id: device_id} =
      AuthFixtures.login!()

    :ok = DeviceBan.ban(app_key, user_id, device_id, "risk", clear_local_data: true)

    assert {:ok, device} = UserDeviceStore.get(app_key, user_id, device_id)
    assert device.clear_local_data_pending
    assert device.banned_at

    assert {:error, %{msg: "device_banned"}} =
             Session.create(%{
               "app_key" => app_key,
               "user_id" => user_id,
               "password" => password,
               "device_id" => device_id,
               "platform" => "ios",
               "sdk_ver" => "1.0"
             })

    # 解封后才能再测 pending；此处直接 ACK pending
    {:ok, _} =
      UserDeviceStore.upsert(%{
        app_key: app_key,
        user_id: user_id,
        device_id: device_id,
        platform: "ios",
        banned_at: nil
      })

    # ban 写入的 banned_at 需清掉才能 ACK 路径独立验证 pending
    device =
      Repo.get_by(IM.Schemas.UserDevice, app_key: app_key, user_id: user_id, device_id: device_id)

    device
    |> Ecto.Changeset.change(%{banned_at: nil, clear_local_data_pending: true})
    |> Repo.update!()

    assert {:ok, cleared} = DeviceBan.ack_local_data_cleared(app_key, user_id, device_id)
    refute cleared.clear_local_data_pending
  end
end
