defmodule IMWeb.Api.V1.MessageControllerTest do
  use IMWeb.ConnCase, async: true

  alias IM.AuthFixtures
  alias IM.Domain.MessageContext
  alias IM.Services.Message
  alias Pb.Im.Protocol.ChatMessage

  test "POST /api/v1/messages 与 Service 同路径" do
    alice = AuthFixtures.login!()
    bob = AuthFixtures.create_user!(app_key: alice.app_key)

    conn =
      build_conn()
      |> put_req_header("x-trace-id", "http-msg-1")
      |> put_req_header("authorization", "Bearer #{alice.token}")
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/v1/messages", %{
        to: bob.user_id,
        content: "hi via rest",
        client_msg_id: "rest-1-#{System.unique_integer([:positive])}"
      })

    assert %{
             "msg_id" => msg_id,
             "client_msg_id" => client,
             "conv_seq" => 1,
             "status" => "SERVER_RECEIVED",
             "duplicate" => false
           } = json_response(conn, 200)

    assert is_binary(msg_id)

    conn2 =
      build_conn()
      |> put_req_header("x-trace-id", "http-msg-2")
      |> put_req_header("authorization", "Bearer #{alice.token}")
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/v1/messages", %{
        to: bob.user_id,
        content: "hi via rest",
        client_msg_id: client
      })

    body2 = json_response(conn2, 200)
    assert body2["msg_id"] == msg_id
    assert body2["duplicate"] == true
  end

  test "REST 与 WS Service 返回同一 msg_id（业务幂等）" do
    alice = AuthFixtures.login!()
    bob = AuthFixtures.create_user!(app_key: alice.app_key)
    client_msg_id = "dual-#{System.unique_integer([:positive])}"

    ctx = %MessageContext{
      app_key: alice.app_key,
      user_id: alice.user_id,
      device_id: alice.device_id,
      session_id: "ws-sess",
      trace_id: "t",
      node: node()
    }

    assert {:ok, ws} =
             Message.send(
               %ChatMessage{
                 chat_type: :CHAT_PRIVATE,
                 from: alice.user_id,
                 to: bob.user_id,
                 msg_type: :MSG_TEXT,
                 content: "dual",
                 client_msg_id: client_msg_id
               },
               ctx
             )

    conn =
      build_conn()
      |> put_req_header("x-trace-id", "http-dual")
      |> put_req_header("authorization", "Bearer #{alice.token}")
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/v1/messages", %{
        to: bob.user_id,
        content: "dual",
        client_msg_id: client_msg_id
      })

    assert json_response(conn, 200)["msg_id"] == ws.message.msg_id
  end
end
