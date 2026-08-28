# 编辑消息 - Elixir 实现

| 项 | 内容 |
|------|------|
| 语言 | Elixir |
| 设计文档 | [edit.md](../../design/edit.md) |
| Roadmap | Phase 7（P7-04） |

> **文档分级**：边缘模块 impl。行为规范见设计文档；本文仅列模块与测试要点。

---

## 1. 模块

| 模块 | 职责 |
|------|------|
| `IM.WebSocket.Commands.MsgEdit` | `CMD_MSG_EDIT_REQ` |
| `IM.Services.Message.Edit` | 权限、时间窗、内容更新 |
| `IM.Delivery.Router` | `CMD_MSG_EDIT_PUSH` 扇出 |

---

## 2. 处理

```elixir
def edit(%{msg_id: msg_id, content: new_content}, ctx) do
  with {:ok, msg} <- MessageStore.get(msg_id, ctx.app_key),
       :ok <- authorize_edit(msg, ctx),
       :ok <- within_edit_window?(msg),
       {:ok, updated} <- MessageStore.update_content(msg, new_content) do
    broadcast_edit(updated, ctx)
    {:ok, updated}
  else
    {:error, :timeout} -> {:error, :CODE_MSG_EDIT_DENIED}
  end
end
```

聊天室编辑窗口通常短于单聊/群聊，配置化 `edit_window_seconds`。

---

## 3. 验收要点

- 编辑成功推送 `CMD_MSG_EDIT_PUSH`
- 超时返回 `CMD_ERROR(2005)`
