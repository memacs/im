defmodule IMWeb.Plugs.RequireCallerServiceTest do
  use IMWeb.ConnCase, async: false

  test "非法 caller 返回 400" do
    conn =
      build_conn()
      |> put_req_header("x-trace-id", "tr")
      |> put_req_header("x-im-caller-service", "Bad_Name!")
      |> post(~p"/internal/v1/channels/fleet/alert/publish", %{app_key: "x"})

    assert json_response(conn, 400)["msg"] == "invalid_caller_service"
  end

  test "允许名单拒绝" do
    prev = Application.get_env(:im, :internal_api)
    Application.put_env(:im, :internal_api, allowed_callers: ["ops"], blocked_callers: [])

    on_exit(fn ->
      if prev, do: Application.put_env(:im, :internal_api, prev), else: Application.delete_env(:im, :internal_api)
    end)

    conn =
      build_conn()
      |> put_req_header("x-trace-id", "tr")
      |> put_req_header("x-im-caller-service", "other")
      |> post(~p"/internal/v1/channels/fleet/alert/publish", %{app_key: "x"})

    assert json_response(conn, 403)["msg"] == "caller_not_allowed"
  end
end
