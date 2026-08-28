# 已读回执 - Elixir 实现

| 项 | 内容 |
|------|------|
| 语言 | Elixir |
| 设计文档 | [read-receipt.md](../../design/read-receipt.md) |
| Roadmap | Phase 7（P7-02） |

> **文档分级**：边缘模块 impl。行为规范见设计文档；本文仅列模块与测试要点。

---

## 1. 模块

| 模块 | 职责 |
|------|------|
| `IM.WebSocket.Commands.MsgRead` | `CMD_MSG_READ` 处理 |
| `IM.Stores.ConversationStore` | 更新 `read_conv_seq` |
| `IM.Delivery.Router` | 单聊通知对端；群聊仅本用户 |
| `IM.Services.Message.BurnScheduler` | 单聊阅后即焚：READ 覆盖后调度 `MessageBurn` Job（见 [burn-after-read.md](burn-after-read.md)） |

---

## 2. 处理流程

```elixir
def handle(packet, socket) do
  with {:ok, read} <- decode(packet),
       :ok <- authorize(read, socket.assigns),
       :ok <- ConversationStore.update_read_cursor(read, socket.assigns) do
    maybe_notify_peer(read, socket.assigns)
    maybe_sync_other_devices(read, socket.assigns)
    BurnScheduler.on_read(read, socket.assigns)  # 阅后即焚
    {:ok, IM.Protocol.Reply.ok(packet, :CMD_MSG_READ, read)}
  end
end
```

| chat_type | 行为 |
|-----------|------|
| 单聊 | 通知对端 + 同步自己其他设备 |
| 群聊 | 仅更新本用户游标，不广播给其他成员 |
| 聊天室 | 不支持 |

---

## 3. 验收要点

- 单聊已读对端收到 `CMD_MSG_READ` 推送
- 群聊已读不推送给其他群成员
- 单聊阅后即焚：对端 READ 后调度销毁（见 P7-09 / [burn-after-read.md](burn-after-read.md)）
