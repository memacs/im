defmodule IMWeb.Api.V1.DeviceControllerTest do
  use IMWeb.ConnCase, async: true

  alias IM.AuthFixtures

  defp auth_conn(login, trace) do
    build_conn()
    |> put_req_header("x-trace-id", trace)
    |> put_req_header("authorization", "Bearer #{login.token}")
    |> put_req_header("content-type", "application/json")
  end

  test "push-token + local-data-cleared + ban" do
    login = AuthFixtures.login!()
    dev = login.device_id

    pt =
      auth_conn(login, "pt")
      |> put(~p"/api/v1/devices/#{dev}/push-token", %{push_token: "apns-token"})

    assert %{"device_id" => ^dev, "push_token_registered" => true} = json_response(pt, 200)

    cleared =
      auth_conn(login, "clr")
      |> post(~p"/api/v1/devices/#{dev}/local-data-cleared", %{})

    assert response(cleared, 204)

    ban =
      auth_conn(login, "ban")
      |> post(~p"/api/v1/devices/#{dev}/ban", %{reason: "test", clear_local_data: true})

    assert response(ban, 204)
  end

  test "device_id 不匹配返回 401" do
    login = AuthFixtures.login!()

    conn =
      auth_conn(login, "bad-dev")
      |> post(~p"/api/v1/devices/other-device/local-data-cleared", %{})

    assert json_response(conn, 401)["msg"] =~ "device_id"
  end
end
