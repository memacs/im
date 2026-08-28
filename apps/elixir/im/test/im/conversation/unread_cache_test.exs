defmodule IM.Conversation.UnreadCacheTest do
  use IM.DataCase, async: false

  alias IM.Cache.Memory
  alias IM.Conversation.UnreadCache
  alias IM.Jobs.UnreadFlush
  alias IM.Stores.ConversationStore

  setup do
    Memory.reset!()
    :ok
  end

  test "incr / pending / reset" do
    app = "app_demo"
    user = "u1"
    conv = "p:a:b"

    assert UnreadCache.pending(app, user, conv) == 0
    :ok = UnreadCache.incr(app, user, conv)
    :ok = UnreadCache.incr(app, user, conv)
    assert UnreadCache.pending(app, user, conv) == 2
    assert [{^user, ^conv}] = UnreadCache.list_dirty(app, 10)

    :ok = UnreadCache.reset(app, user, conv)
    assert UnreadCache.pending(app, user, conv) == 0
    assert UnreadCache.list_dirty(app, 10) == []
  end

  test "get_unread 合并 PG 基线与 Redis pending" do
    app = "app_demo"
    user = "u2"
    conv = "p:x:y"

    assert {:ok, _} =
             ConversationStore.upsert_read(app, user, conv, 1, chat_type: 1, peer_id: "x")

    :ok = ConversationStore.bump_unread(app, user, conv, chat_type: 1, peer_id: "x")
    assert ConversationStore.get_unread(app, user, conv) == 1

    assert {:ok, _} =
             ConversationStore.upsert_read(app, user, conv, 2, chat_type: 1, peer_id: "x")

    assert ConversationStore.get_unread(app, user, conv) == 0
  end

  test "flush_pending 将 pending 写入 PG 并清空 Redis" do
    app = "app_demo"
    user = "u3"
    conv = "p:m:n"

    :ok = ConversationStore.bump_unread(app, user, conv, chat_type: 1, peer_id: "m")
    assert ConversationStore.get_unread(app, user, conv) == 1

    assert %{flushed: 1} = UnreadFlush.run_once(app_key: app)
    assert ConversationStore.get_unread(app, user, conv) == 1
    assert UnreadCache.pending(app, user, conv) == 0

    row = IM.Repo.get_by!(IM.Schemas.Conversation, app_key: app, user_id: user, conv_id: conv)
    assert row.unread_count == 1
  end
end
