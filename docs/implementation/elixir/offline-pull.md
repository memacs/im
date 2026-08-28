# 离线拉取 - Elixir 实现

| 项 | 内容 |
|------|------|
| 语言 | Elixir |
| 设计文档 | [offline-pull.md](../../design/offline-pull.md) |
| Roadmap | Phase 4（P4-01 ~ P4-05） |

> **文档分级**：边缘模块 impl。行为规范见设计文档；本文仅列模块与测试要点。

---

## 1. 模块

| 模块 | 职责 |
|------|------|
| `IM.WebSocket.Commands.OfflinePull` | `CMD_OFFLINE_PULL_REQ` / `RESP` |
| `IM.Services.Offline` | 分页查询收件箱 |
| `IM.Stores.MessageStore` | 单聊/群聊：`user_inbox` JOIN `message_bodies` |

---

## 2. 分页查询

单聊与群聊共用 `list_inbox_joined` / `list_conv_joined`（见设计 [database-design.md](../../design/database/database-design.md) §3 SQL）：

```elixir
def pull(app_key, user_id, %{cursor: cursor, limit: limit, conv_id: nil}) do
  MessageStore.list_inbox_joined(app_key, user_id, after_seq: cursor, limit: limit)
end

def pull(app_key, user_id, %{cursor: cursor, limit: limit, conv_id: conv_id}) do
  MessageStore.list_conv_joined(app_key, user_id, conv_id, after_seq: cursor, limit: limit)
end
```

仅 `CHAT_PRIVATE` / `CHAT_GROUP` 走本路径；聊天室不出现在 `OFFLINE_PULL` 结果中。

---

## 3. 写扩散分片

`user_inbox` 分片键 `(app_key, user_id)`。每条消息：`message_bodies` 1 行 + 每收件人 `user_inbox` 1 瘦行（单聊 2 行、群聊 N 行）。

---

## 4. 验收要点

- AUTH 后 OFFLINE_PULL 按 `inbox_seq` 递增返回
- `has_more` 与 `next_cursor` 正确
- 聊天室消息不出现在 OFFLINE_PULL 结果中
