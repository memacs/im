defmodule IM.Client.Protocol.FriendTest do
  @moduledoc "好友：申请/接受/拒绝/删除/拉黑/列表/备注/请求列表。"
  use IM.ClientProtocolCase

  alias IM.Client.Connection
  alias Pb.Im.Protocol.{
    FriendAddResp,
    FriendAcceptResp,
    FriendBlockResp,
    FriendDeleteResp,
    FriendListResp,
    FriendRejectResp,
    FriendRequestListResp,
    FriendSetRemarkReq,
    FriendSetRemarkResp,
    FriendUnblockResp
  }

  @tag trace_case: "friend_test/添加-接受-列表-备注-删除"
  test "添加-接受-列表-备注-删除" do
    %{a: a, b: b} = connect_pair!()

    trace_as!("A")
    {:ok, add_packet} = Connection.add_friend(a.client, %{to_user_id: b.login.user_id, message: "hi"})
    trace!("↓ WS CMD_FRIEND_ADD_RESP", add_packet)
    add = assert_cmd_resp!(add_packet, :CMD_FRIEND_ADD_RESP, FriendAddResp)

    trace_as!("B")
    {:ok, accept_packet} =
      Connection.accept_friend(b.client, %{request_id: add.request_id, from_user_id: a.login.user_id})

    trace!("↓ WS CMD_FRIEND_ACCEPT_RESP", accept_packet)
    assert_cmd_resp!(accept_packet, :CMD_FRIEND_ACCEPT_RESP, FriendAcceptResp)

    trace_as!("A")
    {:ok, list_packet} = Connection.list_friends(a.client)
    trace!("↓ WS CMD_FRIEND_LIST_RESP", list_packet)
    list = assert_cmd_resp!(list_packet, :CMD_FRIEND_LIST_RESP, FriendListResp)
    assert Enum.any?(list.friends, &(&1.user_id == b.login.user_id))

    trace!("↑ WS CMD_FRIEND_SET_REMARK_REQ", %FriendSetRemarkReq{
      friend_user_id: b.login.user_id,
      remark: "buddy"
    })

    {:ok, remark_packet} =
      Connection.request(a.client, :CMD_FRIEND_SET_REMARK_REQ, %FriendSetRemarkReq{
        friend_user_id: b.login.user_id,
        remark: "buddy"
      })

    trace!("↓ WS CMD_FRIEND_SET_REMARK_RESP", remark_packet)
    assert_cmd_resp!(remark_packet, :CMD_FRIEND_SET_REMARK_RESP, FriendSetRemarkResp)

    {:ok, del_packet} = Connection.delete_friend(a.client, b.login.user_id)
    trace!("↓ WS CMD_FRIEND_DELETE_RESP", del_packet)
    assert_cmd_resp!(del_packet, :CMD_FRIEND_DELETE_RESP, FriendDeleteResp)
  end

  @tag trace_case: "friend_test/拒绝好友请求"
  test "拒绝好友请求" do
    %{a: a, b: b} = connect_pair!()

    trace_as!("A")
    {:ok, add_packet} = Connection.add_friend(a.client, %{to_user_id: b.login.user_id})
    add = assert_cmd_resp!(add_packet, :CMD_FRIEND_ADD_RESP, FriendAddResp)
    trace!("↓ WS CMD_FRIEND_ADD_RESP", add_packet)

    trace_as!("B")
    {:ok, rej_packet} =
      Connection.reject_friend(b.client, %{request_id: add.request_id, from_user_id: a.login.user_id})

    trace!("↓ WS CMD_FRIEND_REJECT_RESP", rej_packet)
    assert_cmd_resp!(rej_packet, :CMD_FRIEND_REJECT_RESP, FriendRejectResp)
  end

  @tag trace_case: "friend_test/拉黑与取消拉黑"
  test "拉黑与取消拉黑" do
    %{a: a, b: b} = connect_pair!()

    trace_as!("A")
    {:ok, block_packet} = Connection.block_friend(a.client, b.login.user_id)
    trace!("↓ WS CMD_FRIEND_BLOCK_RESP", block_packet)
    assert_cmd_resp!(block_packet, :CMD_FRIEND_BLOCK_RESP, FriendBlockResp)

    {:ok, denied_packet} =
      Connection.send_message(a.client, %{
        to: b.login.user_id,
        chat_type: :CHAT_PRIVATE,
        content: "blocked"
      })

    trace!("↓ WS CMD_ERROR (拉黑后发消息)", denied_packet)
    assert denied_packet.cmd == CmdType.value(:CMD_ERROR)

    {:ok, unblock_packet} = Connection.unblock_friend(a.client, b.login.user_id)
    trace!("↓ WS CMD_FRIEND_UNBLOCK_RESP", unblock_packet)
    assert_cmd_resp!(unblock_packet, :CMD_FRIEND_UNBLOCK_RESP, FriendUnblockResp)

    {msg_id, _} = send_private!(a.client, a.login.user_id, b.login.user_id, content: "ok")
    assert msg_id != ""
  end

  @tag trace_case: "friend_test/好友请求列表"
  test "好友请求列表" do
    %{a: a, b: b} = connect_pair!()
    trace_as!("A")
    {:ok, _} = Connection.add_friend(a.client, %{to_user_id: b.login.user_id})

    trace_as!("B")
    trace!("↑ WS CMD_FRIEND_REQUEST_LIST_REQ", %Pb.Im.Protocol.FriendRequestListReq{limit: 20})

    {:ok, packet} =
      Connection.request(b.client, :CMD_FRIEND_REQUEST_LIST_REQ, %Pb.Im.Protocol.FriendRequestListReq{
        limit: 20
      })

    trace!("↓ WS CMD_FRIEND_REQUEST_LIST_RESP", packet)
    resp = assert_cmd_resp!(packet, :CMD_FRIEND_REQUEST_LIST_RESP, FriendRequestListResp)
    assert Enum.any?(resp.requests, &(&1.from_user_id == a.login.user_id))
  end
end
