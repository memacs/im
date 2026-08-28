defmodule IM.Services.SessionTest do
  use IM.DataCase, async: true

  alias IM.AuthFixtures
  alias IM.Domain.Error
  alias IM.Services.{DeviceBan, Session}
  alias IM.Stores.UserDeviceStore

  describe "create/1" do
    test "合法凭证签发 token 与 connection" do
      %{password: password, app_key: app_key, user_id: user_id} = AuthFixtures.create_user!()

      assert {:ok, body} =
               Session.create(%{
                 "app_key" => app_key,
                 "user_id" => user_id,
                 "password" => password,
                 "device_id" => "d1",
                 "platform" => "ios",
                 "sdk_ver" => "1.0"
               })

      assert is_binary(body.access_token)
      assert body.user_id == user_id
      assert is_list(body.connection.websocket_urls)
      assert body.config.payload_compression == "none"
      assert body.clear_local_data == false
    end

    test "密码错误返回 unauthorized" do
      %{app_key: app_key, user_id: user_id} = AuthFixtures.create_user!()

      assert {:error, %Error{code: :unauthorized}} =
               Session.create(%{
                 "app_key" => app_key,
                 "user_id" => user_id,
                 "password" => "wrong",
                 "device_id" => "d1",
                 "platform" => "ios",
                 "sdk_ver" => "1.0"
               })
    end

    test "设备封禁返回 device_banned" do
      %{app_key: app_key, user_id: user_id, password: password} = AuthFixtures.create_user!()
      {:ok, _} = UserDeviceStore.upsert(%{app_key: app_key, user_id: user_id, device_id: "d1", platform: "ios"})
      :ok = DeviceBan.ban(app_key, user_id, "d1", "admin")

      assert {:error, %Error{msg: "device_banned"}} =
               Session.create(%{
                 "app_key" => app_key,
                 "user_id" => user_id,
                 "password" => password,
                 "device_id" => "d1",
                 "platform" => "ios",
                 "sdk_ver" => "1.0"
               })
    end
  end

  describe "revoke/1" do
    test "吊销后 Auth 校验失败" do
      %{token: token} = AuthFixtures.login!()
      assert :ok = Session.revoke(token)
      assert {:error, %Error{code: :unauthorized}} = IM.Auth.verify_token(token)
    end
  end
end
