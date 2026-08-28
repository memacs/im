defmodule IMWeb.Api.V1.ConversationControllerTest do
  use IMWeb.ConnCase, async: true

  alias IM.AuthFixtures

  test "GET /conversations 返回未读与会话元数据" do
    alice = AuthFixtures.login!()
    bob = AuthFixtures.login!(app_key: alice.app_key)

    send_conn =
      build_conn()
      |> put_req_header("x-trace-id", "conv-list-send")
      |> put_req_header("authorization", "Bearer #{alice.token}")
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/v1/messages", %{
        to: bob.user_id,
        content: "hello",
        client_msg_id: "cl-#{System.unique_integer([:positive])}"
      })

    assert %{"conv_id" => conv_id} = json_response(send_conn, 200)

    list_conn =
      build_conn()
      |> put_req_header("x-trace-id", "conv-list")
      |> put_req_header("authorization", "Bearer #{bob.token}")
      |> get(~p"/api/v1/conversations")

    assert %{"conversations" => convs, "total_unread" => 1} = json_response(list_conn, 200)

    assert Enum.any?(convs, fn c ->
             c["conv_id"] == conv_id and c["unread_count"] == 1 and
               c["last_msg_preview"] == "hello"
           end)
  end
end
