defmodule IMWeb.FallbackControllerTest do
  use IMWeb.ConnCase, async: true

  alias IM.Domain.Error
  alias IMWeb.FallbackController

  test "Error 映射 HTTP 状态" do
    cases = [
      {:unauthorized, 401},
      {:device_limit_exceeded, 403},
      {:msg_invalid, 400},
      {:group_not_found, 404},
      {:group_not_member, 403},
      {:group_no_permission, 403},
      {:friend_not_friend, 403},
      {:friend_blocked, 403},
      {:friend_blocked_by_peer, 403},
      {:rate_limited, 429},
      {:internal, 500}
    ]

    for {code, status} <- cases do
      conn =
        build_conn()
        |> FallbackController.call({:error, Error.new(code, "msg", ref_cmd: 1, ref_cid: "c1")})

      assert conn.status == status
      body = json_response(conn, status)
      assert body["msg"] == "msg"
      assert body["ref_cid"] == "c1"
    end
  end
end
