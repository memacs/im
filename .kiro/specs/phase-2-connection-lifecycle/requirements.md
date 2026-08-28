# Requirements: Phase 2 连接生命周期

| 项 | 内容 |
| --- | --- |
| Spec | `phase-2-connection-lifecycle` |
| Roadmap | Phase 2（P2-01 ~ P2-13） |
| 权威 | `protocol.md` §5–6；`design/auth.md` §7–9 |
| 依赖 | Phase 1 协议适配层 |

---

## User Stories

### US-1：HTTP 登录签发 token

WHEN 客户端 `POST /api/v1/sessions` 提交合法 `app_key/user_id/password/device_id/platform/sdk_ver` 且带头 `X-Trace-Id`，THE SYSTEM SHALL 返回 `access_token`、`expires_at`、`connection.websocket_urls`、`config`、`clear_local_data`，并在 `access_tokens` 仅存 hash。

WHEN 密码错误，THE SYSTEM SHALL 返回 HTTP 401 且不签发 token。

WHEN 设备 `banned_at` 非空，THE SYSTEM SHALL 返回 HTTP 403（`device_banned`）。

WHEN 客户端 `DELETE /api/v1/sessions/current` 带合法 Bearer，THE SYSTEM SHALL 吊销当前 token。

### US-2：二进制 WebSocket + 状态机

WHEN 客户端连接 `/ws`，THE SYSTEM SHALL 接受 **二进制** 帧并忽略/拒绝将文本帧作为业务（可静默关闭或忽略）。

WHEN 连接处于 `unauthenticated`，THE SYSTEM SHALL 仅允许 `CMD_AUTH_REQ`；其它入站业务包导致**静默断开**。

WHEN 建连后 10s 内未成功鉴权，THE SYSTEM SHALL 静默断开。

WHEN 已鉴权后再收到 `CMD_AUTH_REQ`，THE SYSTEM SHALL 回 `CMD_ERROR` 1001 并关闭连接。

WHEN 已鉴权收到未注册 cmd，THE SYSTEM SHALL 回 `CMD_ERROR` 2001 并关闭连接。

### US-3：WS 鉴权与心跳

WHEN `CMD_AUTH_REQ` 携带有效 token 且设备未封禁，THE SYSTEM SHALL 回 `CMD_AUTH_RESP`（含 `clear_local_data`、`payload_compression=NONE` 等），连接进入 `authenticated`，并注册到本节点 Registry。

WHEN token 无效/过期/已吊销/设备封禁，THE SYSTEM SHALL 回 `CMD_ERROR` 1001 并关闭连接。

WHEN 已鉴权收到 `CMD_HEARTBEAT_REQ`，THE SYSTEM SHALL 回 `CMD_HEARTBEAT_RESP`（回传 `seq`），并重置空闲计时。

WHEN 已鉴权连接空闲超过约 90s（无心跳且无业务包），THE SYSTEM SHALL 静默断开。

### US-4：Dispatch 与 REST 管道

WHEN WS Command 或已鉴权 REST 调用业务，THE SYSTEM SHALL 经 `IM.Application.Dispatch` 进入 `IM.Services.*`，适配层不写业务规则。

WHEN REST 带 Bearer token，THE SYSTEM SHALL 与 WS 使用同一套 token 校验。

WHEN Service 返回 `IM.Domain.Error`，THE SYSTEM SHALL 由 `FallbackController` 映射为 HTTP 状态 + JSON（与 ErrorBody 语义对齐）。

### US-5：踢人 / 设备限制 / 清本地数据

WHEN 服务端踢在线设备，THE SYSTEM SHALL 下发 `CMD_KICK`（含 `reason`/`reason_code`/`clear_local_data`）并关闭连接。

WHEN 同平台在线设备数超限且策略为 `reject`，THE SYSTEM SHALL 在 AUTH 时返回 1004 并关连接。

WHEN 封禁设备，THE SYSTEM SHALL 写 `banned_at`、吊销 token、在线则 KICK；后续 sessions 返回 403。

WHEN `clear_local_data_pending`，THE SYSTEM SHALL 在 sessions/`AuthResp` 返回 `clear_local_data=true`，直至 `POST /api/v1/devices/:id/local-data-cleared` ACK。

### US-6：可观测（MVP）

WHEN 处理 WS 包，THE SYSTEM SHALL 发出上下行计数/包大小/耗时 telemetry（标签含 direction；host/msg_type 可有默认值）。

WHEN 生产环境，THE SYSTEM SHALL 默认 logger level `:warning`；业务经 `IM.Log` 输出可解析的单行 JSON 元数据；成功主路径不打 info 日志。

---

## Non-Goals

- 单聊发消息（Phase 3）
- Redis token 缓存 / Tracker 跨节点（Phase 5/9）
- GZIP/LZ4 实际压缩
- 真实租户密码目录对接（MVP 使用本地 `users.password_hash`）
