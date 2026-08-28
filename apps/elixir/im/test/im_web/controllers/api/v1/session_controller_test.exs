defmodule IMWeb.Api.V1.SessionControllerTest do
  use IMWeb.ConnCase, async: true

  alias IM.AuthFixtures

  test "POST /api/v1/sessions 成功" do
    %{password: password, app_key: app_key, user_id: user_id} = AuthFixtures.create_user!()

    conn =
      build_conn()
      |> put_req_header("x-trace-id", "http-tr-1")
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/v1/sessions", %{
        app_key: app_key,
        user_id: user_id,
        password: password,
        device_id: "d-http",
        platform: "web",
        sdk_ver: "1.0"
      })

    assert %{"access_token" => token, "connection" => %{"websocket_urls" => urls}} =
             json_response(conn, 200)

    assert is_binary(token)
    assert is_list(urls)
  end

  test "缺少 X-Trace-Id 返回 400" do
    conn = post(build_conn(), ~p"/api/v1/sessions", %{})
    assert json_response(conn, 400)["msg"] =~ "Trace"
  end

  test "DELETE sessions/current 吊销 token" do
    %{token: token} = AuthFixtures.login!()

    conn =
      build_conn()
      |> put_req_header("x-trace-id", "http-tr-2")
      |> put_req_header("authorization", "Bearer #{token}")
      |> delete(~p"/api/v1/sessions/current")

    assert response(conn, 204)
    assert {:error, _} = IM.Auth.verify_token(token)
  end
end
