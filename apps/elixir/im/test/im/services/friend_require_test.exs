defmodule IM.Services.FriendRequireTest do
  use IM.DataCase, async: true

  alias IM.AuthFixtures
  alias IM.Domain.{Error, MessageContext}
  alias IM.Services.{Friend, Message}
  alias IM.Stores.AppConfigStore
  alias Pb.Im.Protocol.{ChatMessage, FriendAcceptReq, FriendAddReq}

  setup do
    app_key = "app_fr_#{System.unique_integer([:positive])}"

    alice =
      AuthFixtures.create_user!(
        app_key: app_key,
        user_id: "fa_#{System.unique_integer([:positive])}"
      )

    bob =
      AuthFixtures.create_user!(
        app_key: app_key,
        user_id: "fb_#{System.unique_integer([:positive])}"
      )

    alice_ctx = %MessageContext{
      app_key: alice.app_key,
      user_id: alice.user_id,
      device_id: "d-a",
      session_id: "s",
      trace_id: "fr-req",
      node: node()
    }

    bob_ctx = %{alice_ctx | user_id: bob.user_id, device_id: "d-b"}
    %{alice: alice, bob: bob, alice_ctx: alice_ctx, bob_ctx: bob_ctx}
  end

  test "默认关闭：陌生人可单聊", %{alice_ctx: alice_ctx, bob: bob} do
    assert {:ok, _} = send_text(alice_ctx, bob.user_id)
  end

  test "开启后非好友拒绝，成为好友后可发", %{
    alice: alice,
    bob: bob,
    alice_ctx: alice_ctx,
    bob_ctx: bob_ctx
  } do
    assert {:ok, _} =
             AppConfigStore.put(alice.app_key, "friend", "require_friend_to_send", true)

    assert {:error, %Error{code: :friend_not_friend}} = send_text(alice_ctx, bob.user_id)

    assert {:ok, %{resp: %{request_id: rid}}} =
             Friend.add(%FriendAddReq{to_user_id: bob.user_id}, alice_ctx)

    assert {:ok, _} = Friend.accept(%FriendAcceptReq{request_id: rid}, bob_ctx)
    assert {:ok, _} = send_text(alice_ctx, bob.user_id)
  end

  test "check_send_permission 尊重配置", %{alice: alice, bob: bob} do
    assert :ok = Friend.check_send_permission(alice.app_key, alice.user_id, bob.user_id)

    assert {:ok, _} =
             AppConfigStore.put(alice.app_key, "friend", "require_friend_to_send", true)

    assert {:error, %Error{code: :friend_not_friend}} =
             Friend.check_send_permission(alice.app_key, alice.user_id, bob.user_id)
  end

  defp send_text(ctx, to) do
    Message.send(
      %ChatMessage{
        chat_type: :CHAT_PRIVATE,
        to: to,
        msg_type: :MSG_TEXT,
        content: "hi",
        client_msg_id: "fr-#{System.unique_integer([:positive])}"
      },
      ctx
    )
  end
end
