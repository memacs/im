defmodule IM.Client.Protocol.GroupTest do
  @moduledoc "群组：创建/加入/邀请/踢人/管理员/转让/更新/解散 + 群消息。"
  use IM.ClientProtocolCase

  alias IM.Client.{Assertions, Connection}
  alias Pb.Im.Protocol.{GroupCreateResp, GroupTransferReq, GroupUpdateReq}

  @tag trace_case: "group_test/群生命周期与群消息"
  test "群生命周期与群消息" do
    %{a: owner, b: member} = connect_pair!()
    extra = connect_authenticated!(app_key: owner.login.app_key)
    invited = connect_authenticated!(app_key: owner.login.app_key)
    group_id = unique_id("g")

    trace_as!("owner")

    {:ok, create_packet} =
      Connection.create_group(owner.client, %{
        group_id: group_id,
        name: "test-group",
        member_uids: [member.login.user_id]
      })

    trace!("↓ WS CMD_GROUP_CREATE_RESP", create_packet)
    created = assert_cmd_resp!(create_packet, :CMD_GROUP_CREATE_RESP, GroupCreateResp)
    conv_id = created.conv_id

    trace_as!("extra")
    {:ok, join_packet} = Connection.join_group(extra.client, group_id)
    trace!("↓ WS CMD_GROUP_JOIN_PUSH", join_packet)

    trace_as!("owner")

    {:ok, admin_packet} =
      Connection.set_group_admin(owner.client, %{
        group_id: group_id,
        member_uid: member.login.user_id
      })

    trace!("↓ WS CMD_GROUP_SET_ADMIN_PUSH", admin_packet)

    {:ok, rm_admin_packet} =
      Connection.remove_group_admin(owner.client, %{
        group_id: group_id,
        member_uid: member.login.user_id
      })

    trace!("↓ WS CMD_GROUP_REMOVE_ADMIN_PUSH", rm_admin_packet)

    {:ok, msg_packet} =
      Connection.send_message(owner.client, %{
        from: owner.login.user_id,
        to: group_id,
        chat_type: :CHAT_GROUP,
        content: "group-hi",
        route_key: group_id
      })

    trace!("↓ WS CMD_MSG_ACK_DOWN", msg_packet)
    ack = assert_cmd_resp!(msg_packet, :CMD_MSG_ACK_DOWN, Pb.Im.Protocol.MsgAck)

    trace_as!("member")
    push_packet = Assertions.assert_push(member.client) |> elem(1)
    trace!("↓ WS CMD_MSG_PUSH", push_packet)
    push = decode_payload!(push_packet, Pb.Im.Protocol.ChatMessage)
    assert push.content == "group-hi"
    assert push.conv_id == conv_id
    assert ack.msg_id != ""

    trace_as!("extra")
    {:ok, leave_packet} = Connection.leave_group(extra.client, group_id)
    trace!("↓ WS CMD_GROUP_LEAVE_PUSH", leave_packet)

    trace_as!("owner")

    {:ok, transfer_packet} =
      Connection.request(owner.client, :CMD_GROUP_TRANSFER_REQ, %GroupTransferReq{
        group_id: group_id,
        new_owner_uid: member.login.user_id
      })

    trace!("↓ WS CMD_GROUP_TRANSFER_PUSH", transfer_packet)

    trace_as!("member")

    {:ok, update_packet} =
      Connection.request(member.client, :CMD_GROUP_UPDATE_REQ, %GroupUpdateReq{
        group_id: group_id,
        name: "renamed",
        announcement: "ann"
      })

    trace!("↓ WS CMD_GROUP_UPDATE_PUSH", update_packet)

    {:ok, invite_packet} =
      Connection.invite_group_members(member.client, %{
        group_id: group_id,
        member_uids: [invited.login.user_id]
      })

    trace!("↓ WS CMD_GROUP_INVITE_PUSH", invite_packet)

    {:ok, kick_packet} =
      Connection.kick_group_members(member.client, %{
        group_id: group_id,
        member_uids: [owner.login.user_id],
        reason: "test"
      })

    trace!("↓ WS CMD_GROUP_KICK_PUSH", kick_packet)

    {:ok, dismiss_packet} = Connection.dismiss_group(member.client, group_id)
    trace!("↓ WS CMD_GROUP_DISMISS_PUSH", dismiss_packet)
  end
end
