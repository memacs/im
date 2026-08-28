# 心跳 - Elixir 实现

| 项 | 内容 |
|------|------|
| 语言 | Elixir |
| 设计文档 | [heartbeat.md](../../design/heartbeat.md) |
| Roadmap | Phase 2（P2-05） |

> **文档分级**：边缘模块 impl。行为规范见设计文档；本文仅列模块与测试要点。

---

## 1. 模块

| 模块 | 职责 |
|------|------|
| `IM.WebSocket.Commands.Heartbeat` | 处理 `CMD_HEARTBEAT_REQ`，回 `CMD_HEARTBEAT_RESP` |
| `IM.Connection.HeartbeatMonitor` | 服务端主动检测空闲连接（可选） |

---

## 2. Handler 实现

```elixir
defmodule IM.WebSocket.Commands.Heartbeat do
  @behaviour IM.WebSocket.Command

  def handle(packet, %{assigns: %{state: :authenticated}} = socket) do
    resp = IM.Protocol.Reply.ok(packet, :CMD_HEARTBEAT_RESP, %HeartbeatResp{})
    {:reply, resp, touch_last_active(socket)}
  end

  # 不应到达：ConnectionState 已在入口拦截 unauthenticated
  def handle(_packet, _socket), do: {:stop, :state_violation}
end
```

- 仅在 **`:authenticated`** 状态允许入站；`unauthenticated` 由连接状态机静默断开（[auth.md](../../design/auth.md) §7）

- 回传同一 `seq`
- 更新连接 `last_active_at`，供空闲踢线使用

---

## 3. 验收要点

- 已鉴权连接发 `HEARTBEAT_REQ` 得 `HEARTBEAT_RESP`，`seq` 一致
- 未鉴权连接发心跳：**静默断开**（状态机，不发 `CMD_ERROR`）
