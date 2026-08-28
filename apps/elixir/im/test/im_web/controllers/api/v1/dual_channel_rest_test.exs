defmodule IMWeb.Api.V1.DualChannelRestTest do
  use IMWeb.ConnCase, async: true

  alias IM.AuthFixtures

  defp auth_conn(token, trace) do
    build_conn()
    |> put_req_header("x-trace-id", trace)
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("content-type", "application/json")
  end

  test "好友 add + list" do
    alice = AuthFixtures.login!()
    bob = AuthFixtures.create_user!(app_key: alice.app_key)

    conn =
      auth_conn(alice.token, "friend-add")
      |> post(~p"/api/v1/friends", %{to_user_id: bob.user_id, message: "hi"})

    assert %{"request_id" => rid} = json_response(conn, 200)
    assert is_binary(rid)

    conn2 = auth_conn(alice.token, "friend-list") |> get(~p"/api/v1/friends")
    assert %{"friends" => _} = json_response(conn2, 200)
  end

  test "建群 join leave" do
    owner = AuthFixtures.login!()
    member = AuthFixtures.login!(app_key: owner.app_key)

    conn =
      auth_conn(owner.token, "g-create")
      |> post(~p"/api/v1/groups", %{name: "rest-g"})

    assert %{"group_id" => gid} = json_response(conn, 201)

    conn2 =
      auth_conn(member.token, "g-join")
      |> post(~p"/api/v1/groups/#{gid}/join", %{})

    assert %{"group_id" => ^gid} = json_response(conn2, 200)

    conn3 =
      auth_conn(member.token, "g-leave")
      |> post(~p"/api/v1/groups/#{gid}/leave", %{})

    assert %{"group_id" => ^gid} = json_response(conn3, 200)
  end

  test "聊天室 create join + inbox pull" do
    alice = AuthFixtures.login!()
    bob = AuthFixtures.login!(app_key: alice.app_key)

    conn =
      auth_conn(alice.token, "r-create")
      |> post(~p"/api/v1/rooms", %{name: "rest-room"})

    assert %{"room_id" => rid} = json_response(conn, 201)

    conn2 =
      auth_conn(alice.token, "r-join")
      |> post(~p"/api/v1/rooms/#{rid}/join", %{})

    assert %{"room_id" => ^rid} = json_response(conn2, 200)

    msg_conn =
      auth_conn(alice.token, "msg-send")
      |> post(~p"/api/v1/messages", %{
        to: bob.user_id,
        content: "inbox-me",
        client_msg_id: "cm-#{System.unique_integer([:positive])}"
      })

    assert %{"msg_id" => msg_id, "conv_id" => conv_id} = json_response(msg_conn, 200)

    inbox =
      auth_conn(bob.token, "inbox")
      |> get(~p"/api/v1/messages/inbox")

    body = json_response(inbox, 200)
    assert is_list(body["messages"])

    conv =
      auth_conn(alice.token, "conv")
      |> get(~p"/api/v1/conversations/#{conv_id}/messages")

    assert %{"messages" => msgs} = json_response(conv, 200)
    assert Enum.any?(msgs, &(&1["msg_id"] == msg_id))
  end

  test "透传 + 撤回 + 编辑" do
    alice = AuthFixtures.login!()
    bob = AuthFixtures.create_user!(app_key: alice.app_key)

    pt =
      auth_conn(alice.token, "pt")
      |> post(~p"/api/v1/passthrough", %{to: bob.user_id, action: "typing", data: "1"})

    assert %{"ok" => true} = json_response(pt, 200)

    send =
      auth_conn(alice.token, "m1")
      |> post(~p"/api/v1/messages", %{
        to: bob.user_id,
        content: "edit-me",
        client_msg_id: "e-#{System.unique_integer([:positive])}"
      })

    assert %{"msg_id" => msg_id} = json_response(send, 200)

    edit =
      auth_conn(alice.token, "edit")
      |> post(~p"/api/v1/messages/#{msg_id}/edit", %{content: "edited"})

    assert %{"msg_id" => ^msg_id} = json_response(edit, 200)

    recall =
      auth_conn(alice.token, "recall")
      |> post(~p"/api/v1/messages/#{msg_id}/recall", %{})

    assert %{"msg_id" => ^msg_id} = json_response(recall, 200)
  end

  test "ack + read" do
    alice = AuthFixtures.login!()
    bob = AuthFixtures.login!(app_key: alice.app_key)

    send =
      auth_conn(alice.token, "ack-send")
      |> post(~p"/api/v1/messages", %{
        to: bob.user_id,
        content: "ack",
        client_msg_id: "a-#{System.unique_integer([:positive])}"
      })

    assert %{"msg_id" => msg_id, "conv_id" => conv_id, "conv_seq" => seq} =
             json_response(send, 200)

    ack =
      auth_conn(bob.token, "ack")
      |> post(~p"/api/v1/messages/ack", %{msg_id: msg_id, status: "CLIENT_RECEIVED"})

    assert %{"msg_id" => ^msg_id} = json_response(ack, 200)

    read =
      auth_conn(bob.token, "read")
      |> post(~p"/api/v1/messages/read", %{
        conv_id: conv_id,
        conv_seq: seq,
        to: alice.user_id,
        chat_type: "CHAT_PRIVATE"
      })

    assert %{"conv_id" => ^conv_id} = json_response(read, 200)
  end
end
