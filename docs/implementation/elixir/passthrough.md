# 透传信令 - Elixir 实现

| 项 | 内容 |
|------|------|
| 语言 | Elixir |
| 设计文档 | [passthrough.md](../../design/passthrough.md) |
| Roadmap | Phase 7（P7-05） |

> **文档分级**：边缘模块 impl。行为规范见设计文档；本文仅列模块与测试要点。

---

## 1. 模块

| 模块 | 职责 |
|------|------|
| `IM.WebSocket.Commands.Passthrough` | `CMD_PASSTHROUGH` 上下行 |
| `IM.Services.Passthrough` | 路由目标、可选短时持久化 |
| `IM.Delivery.Router` | 推送给目标用户/群/室在线成员 |

---

## 2. 特点

- 不经过标准消息落库主路径（除非配置需要离线透传）
- 上行与下行共用 `CMD_PASSTHROUGH`，`payload = Passthrough`
- 流式消息（AI 对话）可复用透传 + `MSG_STREAM` 组合，见 [stream-message.md](stream-message.md)

```elixir
def handle(packet, socket) do
  with {:ok, pt} <- decode(packet),
       {:ok, recipients} <- IM.Services.Passthrough.route(pt, socket.assigns) do
    IM.Delivery.Router.deliver(pt, recipients, exclude: socket.assigns.device_id)
    {:ok, IM.Protocol.Reply.ok(packet, :CMD_PASSTHROUGH, pt)}
  end
end
```

---

## 3. 验收要点

- 单聊/群聊/聊天室透传到达目标在线成员
- 发送设备不收自身下行（与 PUSH 规则一致）
