defmodule IM.Stores.MessageStoreTest do
  use IM.DataCase, async: true

  alias IM.AuthFixtures
  alias IM.Domain.MessageContext
  alias IM.Services.Message
  alias IM.Stores.MessageStore
  alias Pb.Im.Protocol.ChatMessage

  setup do
    alice = AuthFixtures.create_user!(user_id: "ms_a_#{System.unique_integer([:positive])}")

    bob =
      AuthFixtures.create_user!(
        app_key: alice.app_key,
        user_id: "ms_b_#{System.unique_integer([:positive])}"
      )

    ctx = %MessageContext{
      app_key: alice.app_key,
      user_id: alice.user_id,
      device_id: "d1",
      session_id: "s1",
      trace_id: "ms",
      node: node()
    }

    %{alice: alice, bob: bob, ctx: ctx}
  end

  test "get / preview / client_msg_id", %{alice: alice, bob: bob, ctx: ctx} do
    {:ok, sent} = Message.send(chat(alice, bob, "preview"), ctx)
    mid = sent.message.msg_id

    assert {:ok, body} = MessageStore.get_by_msg_id(alice.app_key, mid)
    assert body.msg_id == mid
    assert {:error, :not_found} = MessageStore.get_by_msg_id(alice.app_key, "missing")

    assert %{^mid => _} = MessageStore.previews_by_msg_ids(alice.app_key, [mid, ""])
    assert MessageStore.previews_by_msg_ids(alice.app_key, []) == %{}

    assert {:ok, ^body} =
             MessageStore.get_by_client_msg_id(
               alice.app_key,
               alice.user_id,
               sent.message.client_msg_id
             )
  end

  test "mark recalled / edited / burned", %{alice: alice, bob: bob, ctx: ctx} do
    {:ok, sent} = Message.send(chat(alice, bob, "edit"), ctx)
    mid = sent.message.msg_id

    assert {:ok, recalled} = MessageStore.mark_recalled(alice.app_key, mid)
    assert recalled.recalled

    {:ok, sent2} =
      Message.send(
        chat(alice, bob, "edit2", "c2-#{System.unique_integer([:positive])}"),
        ctx
      )

    assert {:ok, edited} =
             MessageStore.mark_edited(alice.app_key, sent2.message.msg_id, "new-body")

    assert edited.content == "new-body"
    assert edited.edit_version == 1

    {:ok, burned} = MessageStore.mark_burned(alice.app_key, sent2.message.msg_id)
    assert burned.burned
    assert {:error, :burned} = MessageStore.mark_edited(alice.app_key, sent2.message.msg_id, "x")
    assert {:ok, ^burned} = MessageStore.mark_burned(alice.app_key, sent2.message.msg_id)
  end

  test "insert_private / insert_group / list queries", %{alice: alice, bob: bob} do
    [u1, u2] = Enum.sort([alice.user_id, bob.user_id])
    conv_id = "p:#{u1}:#{u2}"

    cid = "ins-#{System.unique_integer([:positive])}"

    attrs = %{
      app_key: alice.app_key,
      msg_id: "m-#{System.unique_integer([:positive])}",
      client_msg_id: cid,
      from_uid: alice.user_id,
      to_id: bob.user_id,
      conv_id: conv_id,
      conv_seq: System.unique_integer([:positive]),
      chat_type: 1,
      msg_type: 1,
      content: "direct-insert",
      server_time: System.system_time(:millisecond)
    }

    assert {:ok, %{body: body}} = MessageStore.insert_private(attrs, [alice.user_id, bob.user_id])
    assert body.client_msg_id == cid

    assert [_] = MessageStore.list_by_inbox_seq(alice.app_key, alice.user_id, 0, 50)
    assert [_] = MessageStore.list_by_conv_seq(alice.app_key, alice.user_id, conv_id, 0, 50)

    assert {:error, %{code: :msg_invalid}} =
             MessageStore.insert_private(
               attrs
               |> Map.put(:msg_id, "m-dup-#{System.unique_integer([:positive])}")
               |> Map.put(:conv_seq, System.unique_integer([:positive])),
               [alice.user_id, bob.user_id]
             )

    g_attrs =
      attrs
      |> Map.put(:client_msg_id, "g-#{System.unique_integer([:positive])}")
      |> Map.put(:msg_id, "gm-#{System.unique_integer([:positive])}")
      |> Map.put(:chat_type, 2)
      |> Map.put(:conv_id, "g:test-#{System.unique_integer([:positive])}")
      |> Map.put(:conv_seq, System.unique_integer([:positive]))

    assert {:ok, %{inbox: inbox}} =
             MessageStore.insert_group(g_attrs, [alice.user_id, bob.user_id])

    assert length(inbox) == 2

    bo =
      g_attrs
      |> Map.put(:client_msg_id, "bo-#{System.unique_integer([:positive])}")
      |> Map.put(:msg_id, "bo-#{System.unique_integer([:positive])}")
      |> Map.put(:conv_id, "g:body-#{System.unique_integer([:positive])}")
      |> Map.put(:conv_seq, System.unique_integer([:positive]))

    assert {:ok, %{inbox: []}} = MessageStore.insert_body_only(bo)

    assert [_] =
             MessageStore.list_bodies_by_conv_seq(
               alice.app_key,
               g_attrs.conv_id,
               0,
               10,
               alice.user_id
             )
  end

  test "list_burnable / delete / expired helpers", %{alice: alice, bob: bob, ctx: ctx} do
    {:ok, sent} = Message.send(chat(alice, bob, "ttl"), ctx)
    mid = sent.message.msg_id
    conv_id = sent.message.conv_id

    assert [] = MessageStore.list_burnable(alice.app_key, conv_id, 0)

    cutoff = DateTime.utc_now() |> DateTime.add(-365, :day)
    expired = MessageStore.list_expired_msg_ids(alice.app_key, cutoff, 10)
    assert is_list(expired)

    assert %{inbox: _, bodies: _} = MessageStore.delete_messages(alice.app_key, [mid])
    assert {:error, :not_found} = MessageStore.get_by_msg_id(alice.app_key, mid)

    old = DateTime.utc_now() |> DateTime.add(-3600, :second)
    assert 0 = MessageStore.delete_expired_room_bodies(old, 5)
  end

  defp chat(alice, bob, content, client_id \\ nil) do
    %ChatMessage{
      client_msg_id: client_id || "cm-#{System.unique_integer([:positive])}",
      chat_type: :CHAT_PRIVATE,
      from: alice.user_id,
      to: bob.user_id,
      msg_type: :MSG_TEXT,
      content: content
    }
  end
end
