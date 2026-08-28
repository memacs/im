defmodule IM.Client.Protocol.FriendPolicyTest do
  @moduledoc "好友策略：租户开启「须为好友才能单聊」。"
  use IM.ClientProtocolCase

  alias IM.Client.Connection
  alias IM.Stores.AppConfigStore
  alias Pb.Im.Protocol.{FriendAcceptReq, FriendAddResp}

  @tag trace_case: "friend_policy_test/require_friend_to_send"
  test "require_friend_to_send：非好友被拒，成为好友后可发" do
    app_key = "app_fp_#{System.unique_integer([:positive])}"
    user = AuthFixtures.create_user!(app_key: app_key)

    assert {:ok, _} = AppConfigStore.put(app_key, "friend", "require_friend_to_send", true)

    a =
      connect_authenticated!(
        AuthFixtures.login!(Map.take(user, [:app_key, :user_id, :password]))
      )

    b =
      connect_authenticated!(
        AuthFixtures.login!(
          app_key: app_key,
          user_id: "fp_b_#{System.unique_integer([:positive])}"
        )
      )

    trace_as!("A")
    {:ok, denied} =
      Connection.send_message(a.client, %{
        from: a.login.user_id,
        to: b.login.user_id,
        chat_type: :CHAT_PRIVATE,
        content: "stranger"
      })

    trace!("↓ WS CMD_ERROR (非好友)", denied)
    assert_cmd_error!(denied, :CODE_FRIEND_NOT_FRIEND)

    {:ok, add_packet} =
      Connection.add_friend(a.client, %{to_user_id: b.login.user_id, message: "hi"})

    add = assert_cmd_resp!(add_packet, :CMD_FRIEND_ADD_RESP, FriendAddResp)
    trace!("↓ WS CMD_FRIEND_ADD_RESP", add_packet)

    trace_as!("B")
    trace!("↑ WS CMD_FRIEND_ACCEPT_REQ", %FriendAcceptReq{
      request_id: add.request_id,
      from_user_id: a.login.user_id
    })

    {:ok, accept_packet} =
      Connection.accept_friend(b.client, %{
        request_id: add.request_id,
        from_user_id: a.login.user_id
      })

    trace!("↓ WS CMD_FRIEND_ACCEPT_RESP", accept_packet)

    trace_as!("A")
    {msg_id, _} = send_private!(a.client, a.login.user_id, b.login.user_id, content: "friend-ok")
    assert msg_id != ""
  end
end
