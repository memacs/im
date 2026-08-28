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
    bob = AuthFixtures.login!(app_key: alice.app_key)

    conn =
      auth_conn(alice.token, "friend-add")
      |> post(~p"/api/v1/friends", %{to_user_id: bob.user_id, message: "hi", remark: "bob"})

    assert %{"request_id" => rid} = json_response(conn, 200)
    assert is_binary(rid)

    req_list =
      auth_conn(bob.token, "friend-req")
      |> get(~p"/api/v1/friends/requests")

    assert %{"requests" => _} = json_response(req_list, 200)

    accept =
      auth_conn(bob.token, "friend-acc")
      |> post(~p"/api/v1/friends/accept", %{
        request_id: rid,
        from_user_id: alice.user_id,
        remark: "alice"
      })

    assert json_response(accept, 200)

    remark =
      auth_conn(alice.token, "friend-rmk")
      |> put(~p"/api/v1/friends/remark", %{friend_user_id: bob.user_id, remark: "best"})

    assert json_response(remark, 200)

    conn2 = auth_conn(alice.token, "friend-list") |> get(~p"/api/v1/friends")
    assert %{"friends" => _} = json_response(conn2, 200)

    block =
      auth_conn(alice.token, "friend-blk")
      |> post(~p"/api/v1/friends/block", %{user_id: bob.user_id})

    assert json_response(block, 200)

    unblock =
      auth_conn(alice.token, "friend-unblk")
      |> post(~p"/api/v1/friends/unblock", %{user_id: bob.user_id})

    assert json_response(unblock, 200)

    del =
      auth_conn(alice.token, "friend-del")
      |> delete(~p"/api/v1/friends", %{friend_user_id: bob.user_id})

    assert json_response(del, 200)
  end

  test "好友 reject" do
    alice = AuthFixtures.login!()
    bob = AuthFixtures.login!(app_key: alice.app_key)

    conn =
      auth_conn(alice.token, "friend-add2")
      |> post(~p"/api/v1/friends", %{to_user_id: bob.user_id})

    assert %{"request_id" => rid} = json_response(conn, 200)

    reject =
      auth_conn(bob.token, "friend-rej")
      |> post(~p"/api/v1/friends/reject", %{request_id: rid})

    assert json_response(reject, 200)
  end

  test "建群 join leave" do
    owner = AuthFixtures.login!()
    member = AuthFixtures.login!(app_key: owner.app_key)
    invitee = AuthFixtures.login!(app_key: owner.app_key)

    conn =
      auth_conn(owner.token, "g-create")
      |> post(~p"/api/v1/groups", %{
        name: "rest-g",
        announcement: "hello",
        max_members: 200
      })

    assert %{"group_id" => gid, "member_count" => _} = json_response(conn, 201)

    conn2 =
      auth_conn(member.token, "g-join")
      |> post(~p"/api/v1/groups/#{gid}/join", %{})

    assert %{"group_id" => ^gid} = json_response(conn2, 200)

    invite =
      auth_conn(owner.token, "g-invite")
      |> post(~p"/api/v1/groups/#{gid}/invite", %{member_uids: [invitee.user_id]})

    assert json_response(invite, 200)

    admin =
      auth_conn(owner.token, "g-admin")
      |> post(~p"/api/v1/groups/#{gid}/admins", %{member_uid: member.user_id})

    assert json_response(admin, 200)

    update =
      auth_conn(owner.token, "g-upd")
      |> patch(~p"/api/v1/groups/#{gid}", %{name: "rest-g2", announcement: "upd"})

    assert json_response(update, 200)["name"] == "rest-g2"

    mute =
      auth_conn(owner.token, "g-mute")
      |> post(~p"/api/v1/groups/#{gid}/mute", %{
        member_uid: member.user_id,
        muted_until: System.system_time(:millisecond) + 60_000
      })

    assert json_response(mute, 200)

    kick =
      auth_conn(owner.token, "g-kick")
      |> post(~p"/api/v1/groups/#{gid}/kick", %{member_uids: [invitee.user_id], reason: "test"})

    assert json_response(kick, 200)

    transfer =
      auth_conn(owner.token, "g-xfer")
      |> post(~p"/api/v1/groups/#{gid}/transfer", %{new_owner_uid: member.user_id})

    assert json_response(transfer, 200)

    leave_owner =
      auth_conn(owner.token, "g-leave-owner")
      |> post(~p"/api/v1/groups/#{gid}/leave", %{})

    assert %{"group_id" => ^gid} = json_response(leave_owner, 200)

    dismiss =
      auth_conn(member.token, "g-dismiss")
      |> post(~p"/api/v1/groups/#{gid}/dismiss", %{reason: "done"})

    assert json_response(dismiss, 200)
  end

  test "加入不存在的群返回 404" do
    login = AuthFixtures.login!()

    conn =
      auth_conn(login.token, "g-miss")
      |> post(~p"/api/v1/groups/g_missing_#{System.unique_integer([:positive])}/join", %{})

    assert json_response(conn, 404)["code"]
  end

  test "聊天室 create join + inbox pull" do
    alice = AuthFixtures.login!()
    bob = AuthFixtures.login!(app_key: alice.app_key)

    conn =
      auth_conn(alice.token, "r-create")
      |> post(~p"/api/v1/rooms", %{
        name: "rest-room",
        max_members: 100,
        persist_msg: true,
        msg_ttl_sec: 3600
      })

    assert %{"room_id" => rid} = json_response(conn, 201)

    conn2 =
      auth_conn(alice.token, "r-join")
      |> post(~p"/api/v1/rooms/#{rid}/join", %{})

    assert %{"room_id" => ^rid} = json_response(conn2, 200)

    bob_join =
      auth_conn(bob.token, "r-join-b")
      |> post(~p"/api/v1/rooms/#{rid}/join", %{})

    assert %{"room_id" => ^rid} = json_response(bob_join, 200)

    update =
      auth_conn(alice.token, "r-upd")
      |> patch(~p"/api/v1/rooms/#{rid}", %{name: "renamed", persist_msg: false})

    assert json_response(update, 200)["name"] == "renamed"

    room_msg =
      auth_conn(alice.token, "r-msg")
      |> post(~p"/api/v1/rooms/#{rid}/messages", %{
        client_msg_id: "rm-#{System.unique_integer([:positive])}",
        content: "room-broadcast"
      })

    assert %{"msg_id" => _, "conv_id" => _} = json_response(room_msg, 200)

    kick =
      auth_conn(alice.token, "r-kick")
      |> post(~p"/api/v1/rooms/#{rid}/kick", %{member_uids: [bob.user_id], reason: "test"})

    assert json_response(kick, 200)

    dismiss =
      auth_conn(alice.token, "r-dismiss")
      |> post(~p"/api/v1/rooms/#{rid}/dismiss", %{reason: "done"})

    assert json_response(dismiss, 200)

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

    batch =
      auth_conn(bob.token, "ack-batch")
      |> post(~p"/api/v1/messages/ack-batch", %{
        acks: [
          %{
            msg_id: msg_id,
            client_msg_id: "a-#{System.unique_integer([:positive])}",
            conv_seq: seq
          }
        ]
      })

    assert %{"batches" => batches} = json_response(batch, 200)
    assert is_list(batches)
  end

  test "重复 client_msg_id 返回 duplicate" do
    alice = AuthFixtures.login!()
    bob = AuthFixtures.login!(app_key: alice.app_key)
    cid = "dup-#{System.unique_integer([:positive])}"

    send1 =
      auth_conn(alice.token, "dup1")
      |> post(~p"/api/v1/messages", %{
        to: bob.user_id,
        content: "once",
        client_msg_id: cid
      })

    assert %{"duplicate" => false} = json_response(send1, 200)

    send2 =
      auth_conn(alice.token, "dup2")
      |> post(~p"/api/v1/messages", %{
        to: bob.user_id,
        content: "once",
        client_msg_id: cid
      })

    assert %{"duplicate" => true} = json_response(send2, 200)
  end
end
