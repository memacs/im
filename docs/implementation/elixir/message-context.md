# 消息上下文 - Elixir 实现

| 项 | 内容 |
|------|------|
| 语言 | Elixir |
| 设计文档 | [message-context.md](../../design/message-context.md) |
| Roadmap | Phase 3+（贯穿各命令处理器） |

> **文档分级**：边缘模块 impl。行为规范见设计文档；本文仅列模块与测试要点。

---

## 1. 结构定义

```elixir
defmodule IM.Domain.MessageContext do
  @enforce_keys [:app_key, :user_id, :device_id, :trace_id]

  defstruct [
    :app_key,
    :user_id,
    :device_id,
    :session_id,
    :platform,
    :trace_id,
    :node,
    :connected_at
  ]

  def from_socket(socket) do
    assigns = socket.assigns

    %__MODULE__{
      app_key: assigns.app_key,
      user_id: assigns.user_id,
      device_id: assigns.device_id,
      session_id: assigns.session_id,
      platform: assigns.platform,
      trace_id: assigns[:trace_id],
      node: Node.self(),
      connected_at: assigns[:connected_at]
    }
  end
end
```

---

## 2. 传递规则

| 层级 | 用法 |
|------|------|
| WebSocket 命令处理器 | `MessageContext.from_socket/1` |
| 服务层 | 第一个参数或 `opts[:ctx]` |
| 存储层 | 至少携带 `app_key` 做租户隔离 |
| 投递层 | 携带 `trace_id` 写日志 |

禁止在服务层直接读 `socket`；只传 `MessageContext`。

---

## 3. trace_id

**根 trace**（入站，仅此步可 `generate_trace_id/0`）：

- WS：`Packet.trace_id` 非空则用，否则生成
- HTTP：Plug 已校验 `X-Trace-Id` 必填

**继承**（硬约束）：`Reply` / `Push` / Kafka / 日志 **只读** `context.trace_id`，禁止在 Delivery 扇出时新生成。群扇出 N 路 PUSH 同一 trace。

客户端 `ACK_UP` 应继承所响应 PUSH 的 `trace_id`。

设计全文：[message-context.md](../../design/message-context.md) §7.3–§7.4。

---

## 4. 验收要点

- 所有业务命令处理器从 context 取 `app_key` / `user_id`，不信任 payload `from`
- 日志与 Telemetry 携带 `trace_id`
