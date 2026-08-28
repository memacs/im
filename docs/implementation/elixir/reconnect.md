# 重连与恢复 - Elixir 实现

| 项 | 内容 |
|------|------|
| 语言 | Elixir |
| 设计文档 | [reconnect.md](../../design/reconnect.md) |
| Roadmap | Phase 4（P4-04） |

> **文档分级**：边缘模块 impl。行为规范见设计文档；本文仅列模块与测试要点。

---

## 1. 流程

```text
断线 → 重新 WebSocket 建连 → CMD_AUTH_REQ（新 session）
     → CMD_AUTH_RESP 成功
     → CMD_OFFLINE_PULL_REQ（inbox_seq 游标）
     → 补发离线消息 + 继续实时 PUSH
```

重连不单独实现 cmd；复用 Auth + OfflinePull 组合。

---

## 2. 客户端游标

| 字段 | 存储位置 | 说明 |
|------|----------|------|
| `inbox_seq` | 客户端本地 + 服务端校验 | 全量收件箱游标 |
| `conv_seq` | 按会话 | 会话内增量游标 |

服务端 `OfflinePull` 以 `inbox_seq` 为主键分页；`client_msg_id` 幂等保证重连重试不重复落库。

---

## 3. 连接替换

同一 `device_id` 重连时：

1. 新连接 AUTH 成功
2. `Connection.Registry` 替换旧 pid
3. 旧连接若仍存活则主动关闭（避免双连接）

---

## 4. 验收要点

- 断线重连 AUTH 成功后 OFFLINE_PULL 能补齐断线期间消息
- 相同 `client_msg_id` 重发不重复 PUSH
