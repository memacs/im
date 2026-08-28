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

群聊其余成员 inbox 由 `IM.Jobs.GroupInboxFanout` **异步**写入（见 [group.md](../../design/group.md) §6.2）。`MessageStore.list_conv_joined` / `list_by_conv_seq` 必须能在 inbox 缺行时仍按 `conv_seq` 从 `message_bodies` 补齐（实现草稿见 [group.md](group.md) §5.2）。

---

## 4. SDK / 测试客户端补拉顺序

与设计 [offline-pull.md](../../design/offline-pull.md) §3.2 对齐：

```text
AUTH 后：
  1) OFFLINE_PULL(conv_id=空)
  2) 对每个活跃 write_fanout 群：OFFLINE_PULL(conv_id=g:{id}, cursor=watermark)
  3) 对每个 read_fanout 群：OFFLINE_PULL(conv_id=g:{id}, cursor=…)
  4) 进入实时 PUSH（msg_id 去重）
```

`im_client` / `im-console` 实现离线同步时**不得**省略步骤 2。

---

## 5. 验收要点

- AUTH 后 OFFLINE_PULL 按 `inbox_seq` 递增返回
- `has_more` 与 `next_cursor` 正确
- 聊天室消息不出现在 OFFLINE_PULL 结果中
- 异步 fanout 未完成时：仅全局拉取会漏群消息；加上 `conv_seq` 补拉后不漏（P5-11 / P4 联调）
