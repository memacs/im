defmodule IM.Services.FriendTest do
  use IM.DataCase, async: true

  alias IM.AuthFixtures
  alias IM.Domain.MessageContext
  alias IM.Services.{Friend, Message}
  alias IM.Stores.FriendStore

  alias Pb.Im.Protocol.{
    ChatMessage,
    FriendAcceptReq,
    FriendAddReq,
    FriendBlockReq,
    FriendListReq,
    FriendUnblockReq
  }

  setup do
    a = AuthFixtures.create_user!(user_id: "fa_#{System.unique_integer([:positive])}")

    b =
      AuthFixtures.create_user!(
        app_key: a.app_key,
        user_id: "fb_#{System.unique_integer([:positive])}"
      )

    %{a: a, b: b, a_ctx: ctx(a, "da"), b_ctx: ctx(b, "db")}
  end

  test "添加-接受-列表", %{a: a, b: b, a_ctx: a_ctx, b_ctx: b_ctx} do
    assert {:ok, add} =
             Friend.add(%FriendAddReq{to_user_id: b.user_id, message: "hi"}, a_ctx)

    assert add.resp.request_id != ""
    assert add.notify_user_id == b.user_id

    assert {:ok, _} =
             Friend.accept(
               %FriendAcceptReq{request_id: add.resp.request_id, from_user_id: a.user_id},
               b_ctx
             )

    assert {:ok, list} = Friend.list(%FriendListReq{limit: 50}, a_ctx)
    assert Enum.any?(list.resp.friends, &(&1.user_id == b.user_id))
  end

  test "拉黑后单聊被拒", %{a: a, b: b, a_ctx: a_ctx, b_ctx: b_ctx} do
    assert {:ok, _} = Friend.block(%FriendBlockReq{user_id: a.user_id}, b_ctx)
    assert FriendStore.messaging_blocked?(a.app_key, a.user_id, b.user_id)

    assert {:error, %{code: :friend_blocked_by_peer}} =
             Message.send(
               %ChatMessage{
                 chat_type: :CHAT_PRIVATE,
                 to: b.user_id,
                 msg_type: :MSG_TEXT,
                 content: "x",
                 client_msg_id: "c-#{System.unique_integer([:positive])}"
               },
               a_ctx
             )

    assert {:ok, _} = Friend.unblock(%FriendUnblockReq{user_id: a.user_id}, b_ctx)

    assert {:ok, _} =
             Message.send(
               %ChatMessage{
                 chat_type: :CHAT_PRIVATE,
                 to: b.user_id,
                 msg_type: :MSG_TEXT,
                 content: "ok",
                 client_msg_id: "c-#{System.unique_integer([:positive])}"
               },
               a_ctx
             )
  end

  test "Router 注册好友命令" do
    alias IM.Protocol.Router
    alias Pb.Im.Protocol.CmdType

    assert {:ok, IM.WebSocket.Commands.Friend.Add} =
             Router.route(CmdType.value(:CMD_FRIEND_ADD_REQ))

    assert {:ok, IM.WebSocket.Commands.Friend.RequestList} =
             Router.route(CmdType.value(:CMD_FRIEND_REQUEST_LIST_REQ))
  end

  defp ctx(user, device) do
    %MessageContext{
      app_key: user.app_key,
      user_id: user.user_id,
      device_id: device,
      session_id: "s-#{device}",
      trace_id: "t",
      node: node()
    }
  end
end
