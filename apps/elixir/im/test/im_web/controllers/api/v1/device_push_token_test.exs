defmodule IMWeb.Api.V1.DevicePushTokenTest do
  use IMWeb.ConnCase, async: false

  alias IM.AuthFixtures
  alias IM.Stores.UserDeviceStore

  test "PUT push-token 注册成功" do
    user = AuthFixtures.login!()

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{user.token}")
      |> put_req_header("x-trace-id", "tr-push")
      |> put("/api/v1/devices/#{user.device_id}/push-token", %{push_token: "tok-abc"})

    assert json_response(conn, 200)["push_token_registered"] == true

    assert {:ok, device} = UserDeviceStore.get(user.app_key, user.user_id, user.device_id)
    assert device.push_token == "tok-abc"
  end

  test "device_id 不匹配拒绝" do
    user = AuthFixtures.login!()

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer #{user.token}")
      |> put_req_header("x-trace-id", "tr-push2")
      |> put("/api/v1/devices/other-device/push-token", %{push_token: "x"})

    assert json_response(conn, 401)
  end
end
