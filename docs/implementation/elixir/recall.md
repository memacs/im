# 撤回消息 - Elixir 实现

| 项 | 内容 |
|------|------|
| 语言 | Elixir |
| 设计文档 | [recall.md](../../design/recall.md) |
| Roadmap | Phase 7（P7-03） |

> **文档分级**：边缘模块 impl。行为规范见设计文档；本文仅列模块与测试要点。

---

## 1. 模块

| 模块 | 职责 |
|------|------|
| `IM.WebSocket.Commands.MsgRecall` | `CMD_MSG_RECALL_REQ` |
| `IM.Services.Message.Recall` | 权限与时间窗校验、标记撤回 |
| `IM.Delivery.Router` | `CMD_MSG_RECALL_PUSH` 扇出 |

---

## 2. 校验

```elixir
def recall(msg_id, ctx) do
  with {:ok, msg} <- MessageStore.get(msg_id, ctx.app_key),
       :ok <- authorize_recall(msg, ctx),
       :ok <- within_recall_window?(msg) do
    MessageStore.mark_recalled(msg)
    broadcast_recall(msg, ctx)
  else
    {:error, :timeout} -> {:error, :CODE_MSG_RECALL_DENIED}
  end
end
```

- 发送者或管理员可撤回（群聊）
- 超时返回 `CODE_MSG_RECALL_DENIED`（2003）

---

## 3. 验收要点

- 撤回成功推送 `CMD_MSG_RECALL_PUSH` 给会话相关方
- 超时撤回返回 `CMD_ERROR(2003)`
