defmodule IMWeb.Internal.V1.UserDeviceControllerTest do
  use IMWeb.ConnCase, async: false

  alias IM.AuthFixtures

  test "provision user 成功" do
    uid = "prov_#{System.unique_integer([:positive])}"

    conn =
      build_conn()
      |> put_req_header("x-trace-id", "tr-prov")
      |> put_req_header("x-im-caller-service", "loadtest")
      |> post(~p"/internal/v1/users/#{uid}/provision", %{
        app_key: "app_demo",
        password: "secret",
        nickname: uid
      })

    body = json_response(conn, 200)
    assert body["provisioned"] == true
    assert body["user_id"] == uid
    assert {:ok, _} = IM.Stores.UserStore.get("app_demo", uid)
  end

  test "kick user 成功" do
    user = AuthFixtures.login!()

    conn =
      build_conn()
      |> put_req_header("x-trace-id", "tr-kick")
      |> put_req_header("x-im-caller-service", "ops")
      |> post(~p"/internal/v1/users/#{user.user_id}/kick", %{
        app_key: user.app_key,
        reason: "test"
      })

    assert json_response(conn, 200)["ok"] == true
  end

  test "ban device 成功" do
    user = AuthFixtures.login!()

    conn =
      build_conn()
      |> put_req_header("x-trace-id", "tr-ban")
      |> put_req_header("x-im-caller-service", "ops")
      |> post(~p"/internal/v1/devices/#{user.device_id}/ban", %{
        app_key: user.app_key,
        user_id: user.user_id,
        reason: "abuse"
      })

    assert json_response(conn, 200)["banned"] == true
  end

  test "服务端代发消息" do
    alice = AuthFixtures.create_user!()
    bob = AuthFixtures.create_user!(app_key: alice.app_key)

    conn =
      build_conn()
      |> put_req_header("x-trace-id", "tr-msg")
      |> put_req_header("x-im-caller-service", "ops")
      |> post(~p"/internal/v1/users/#{alice.user_id}/messages", %{
        app_key: alice.app_key,
        to: bob.user_id,
        content: "hello-from-internal",
        client_msg_id: "int-#{System.unique_integer([:positive])}"
      })

    body = json_response(conn, 200)
    assert is_binary(body["msg_id"])
    assert body["status"] == "ACK_SERVER_RECEIVED"
  end
end
