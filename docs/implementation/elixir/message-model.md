# 消息模型 - Elixir 实现

| 项 | 内容 |
|------|------|
| 语言 | Elixir |
| 设计文档 | [message-model.md](../../design/message-model.md) |
| Roadmap | Phase 3（P3-01、P3-04） |

> **文档分级**：边缘模块 impl。行为规范见设计文档；本文仅列模块与测试要点。

---

## 1. 模块

| 模块 | 职责 |
|------|------|
| `IM.Domain.Message` | `ChatMessage` 领域结构、校验 |
| `IM.Stores.MessageStore` | 落库、按幂等键查询 |
| `IM.Services.MsgId` | `msg_id` Snowflake 发号（DD-039） |
| `IM.Services.Sequence` | `conv_seq`、`inbox_seq` 分配（Redis `INCR`） |

---

## 2. 存储与协议映射

持久化 **业务体** `ChatMessage`，不存 `Packet` 信封。

```elixir
defmodule IM.Domain.Message do
  @enforce_keys [:app_key, :from, :to, :chat_type, :client_msg_id]

  defstruct [
    :app_key, :msg_id, :client_msg_id, :from, :to,
    :chat_type, :conv_id, :conv_seq, :inbox_seq,
    :content_type, :content, :priority, :created_at
  ]

  def validate_send(%{from: from}, %{user_id: user_id}) when from != user_id do
    {:error, :forged_sender}
  end

  def validate_send(_msg, _ctx), do: :ok
end
```

---

## 3. 会话 ID 规则

| chat_type | conv_id |
|-----------|---------|
| `CHAT_PRIVATE` | `p:{min_uid}:{max_uid}` |
| `CHAT_GROUP` | `g:{group_id}` |
| `CHAT_ROOM` | `r:{room_id}` |

---

## 4. 验收要点

- `from` 必须等于连接上下文 `user_id`
- `to` 与 `chat_type` 一致（用户 ID / 群 ID / 室 ID）
- 落库字段与 `proto/message.proto` 一致
