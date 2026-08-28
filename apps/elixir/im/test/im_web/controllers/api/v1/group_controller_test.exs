defmodule IMWeb.Api.V1.GroupControllerTest do
  use IMWeb.ConnCase, async: true

  alias IM.AuthFixtures

  test "POST /api/v1/groups 建群" do
    owner = AuthFixtures.login!()
    peer = AuthFixtures.create_user!(app_key: owner.app_key)

    conn =
      build_conn()
      |> put_req_header("x-trace-id", "g-create")
      |> put_req_header("authorization", "Bearer #{owner.token}")
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/v1/groups", %{
        name: "squad",
        member_uids: [peer.user_id]
      })

    assert %{
             "group_id" => gid,
             "conv_id" => conv_id,
             "member_count" => 2,
             "storage_mode" => "write_fanout"
           } = json_response(conn, 201)

    assert conv_id == "g:#{gid}"
  end
end
