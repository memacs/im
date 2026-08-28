# Design — Observability Align Wave1

## 组件

| 模块 | 职责 |
|------|------|
| `IM.Log` | 宏门面 + `__log__/4`（白名单 / 采样 / 调用点） |
| `IM.Log.RateLimit` | GenServer：`auth_failed` / `rate_limited` 60s 窗 |
| `IM.Log.Metadata` | 从 Packet / ConnectionState 写 Logger.metadata |
| `IM.WebSocket.Handler` | put metadata；`error_close` → `packet_error` |
| `IM.WebSocket.Commands.Auth` | 失败 → `auth_failed` |
| `IMWeb.PacketTransport` | decode 失败 → `packet_decode_error` |
| `IM.Services.Channel` | 限流静默丢弃 → `channel_publish_dropped` |
| `IM.Hooks.Pipeline` | `hook_failed` → `internal_error` |

## 序列（CMD_ERROR）

```text
Handler.error_close
  → IM.Log.warning(:packet_error, code:, ref_cmd:, reason:)
  → Reply.error + frame_out
```

## 测试策略

- 单元：`log_test.exs` — caller_module、prod 白名单拒绝、RateLimit 采样
- 集成：Handler / Auth / Transport 路径断言 CaptureLog 含 event 名
