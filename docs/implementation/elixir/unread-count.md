# 未读数管理 - Elixir 实现

| 项 | 内容 |
|------|------|
| 语言 | Elixir |
| 设计文档 | [unread-count.md](../../design/unread-count.md) |
| Roadmap | Phase 4+（收件箱未读） |

> **文档分级**：边缘模块 impl。行为规范见设计文档；本文仅列模块与测试要点。

---

## 1. 写入消息时更新未读数

```elixir
def handle_msg_send(message, context) do
  # 1. 落库消息
  {:ok, message} = save_message(message)
  
  # 2. 更新接收方未读数（事务）
  update_unread_count(message.to, message.conv_id, +1)
  
  # 3. 推送
  push_to_recipients(message)
end
```

---

## 2. 已读回执时清零未读数

```elixir
def handle_msg_read(user_id, conv_id, conv_seq) do
  # 事务：更新已读位点 + 清零未读数
  Repo.transaction(fn ->
    # 1. 更新已读位点（隐式或显式存储）
    update_last_read_seq(user_id, conv_id, conv_seq)
    
    # 2. 清零未读数
    Repo.update_all(
      from(c in Conversation,
        where: c.user_id == ^user_id and c.conv_id == ^conv_id,
        set: [unread_count: 0]
      )
    )
  end)
  
  # 3. 推送给其他设备
  push_read_receipt(user_id, conv_id, conv_seq)
end
```

---

## 3. 幂等性处理

```elixir
def update_unread_count(user_id, conv_id, delta) do
  # 方案1: 客户端去重（msg_id）
  # 客户端收到重复消息时，不上报未读数
  
  # 方案2: 服务端去重（推荐）
  # 使用 msg_id 去重，避免重复更新
  case check_msg_delivered?(msg_id) do
    true -> :ok  # 已推送过，跳过
    false ->
      mark_msg_delivered(msg_id)
      increment_unread_count(user_id, conv_id, delta)
  end
end
```

---

## 4. 发送方未读数

```elixir
# 发送消息时，不更新发送方的 unread_count
def handle_msg_send(message, context) do
  # 接收方未读数 +1
  update_unread_count(message.to, message.conv_id, +1)
  
  # 发送方未读数保持为 0（或清零）
  update_unread_count(message.from, message.conv_id, 0)
end
```

---

## 5. 群聊未读数

```elixir
# 群消息写入时，每个成员独立维护未读数
def handle_group_msg_send(message, member_ids) do
  Enum.each(member_ids, fn member_id ->
    # 每个成员的未读数独立计数
    update_unread_count(member_id, message.conv_id, +1)
  end)
end
```

---

## 6. 批量更新优化

```elixir
# 批量更新未读数，减少数据库写入
def batch_update_unread_count(updates) do
  # updates: [{user_id, conv_id, delta}, ...]
  
  Repo.transaction(fn ->
    Enum.each(updates, fn {user_id, conv_id, delta} ->
      Repo.query!(
        "UPDATE conversations SET unread_count = unread_count + $1 WHERE user_id = $2 AND conv_id = $3",
        [delta, user_id, conv_id]
      )
    end)
  end)
end
```

