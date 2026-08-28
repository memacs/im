# 认证模块架构 - Elixir 实现

| 项 | 内容 |
|------|------|
| 语言 | Elixir |
| 设计文档 | [auth-module.md](../../design/auth-module.md)、[auth.md](../../design/auth.md) §9 |
| 关联 | [dual-channel-api.md](dual-channel-api.md) §4.2 |
| Roadmap | Phase 2（P2-03 REST 登录 + P2-02 WS 鉴权） |

> **文档分级**：边缘模块 impl。完整流程见 [auth.md](../../design/auth.md) §9。

---

## 模块

| 模块 | 职责 |
| --- | --- |
| `IM.Services.Session` | `POST /api/v1/sessions`：密码校验、签发 token、返回 `connection` + `config` |
| `IM.Stores.AccessTokenStore` | `access_tokens` 表；hash 存储、`revoked_at` / `expires_at` |
| `IM.Services.DeviceBan` | 封禁设备：写 `user_devices.banned_at`、吊销 token、`CMD_KICK`（可选 `clear_local_data`） |
| `IM.Services.Kick` | 踢用户/设备：在线 `CMD_KICK`；离线写 `clear_local_data_pending` |
| `IM.Auth` | Behaviour：校验 Bearer / `AuthReq.token` |
| `IM.Services.Auth` | `CMD_AUTH_REQ`：调 `IM.Auth` + 设备封禁检查 + DeviceLimit |
| `IMWeb.Api.V1.SessionController` | HTTP 登录 / 登出 |
| `IMWeb.Api.V1.DeviceController` | `POST .../devices/:id/ban`、`POST .../local-data-cleared`（管理端 / SDK ACK，Phase 2+） |

---

## 测试要点

- HTTP 登录成功 → 返回 `access_token`、`expires_at`、`websocket_urls`；DB 有 `access_tokens` 行。
- 本地 token 有效 → WS `AUTH_REQ` 成功；过期 token → `1001` → 客户端应重新 HTTP 登录。
- `expires_at` 过后 REST `401`、WS `token_expired` KICK。
- 封禁设备：HTTP 登录 `403`；在线设备收到 `CMD_KICK` `device_banned`；已签发 token `revoked_at` 非空。
- **清除本地数据**：kick/ban 带 `clear_local_data=true` → 在线 `KickNotify.clear_local_data`；离线 `user_devices.clear_local_data_pending` → 下次 `sessions` / `AuthResp` 返回 `clear_local_data`；ACK 后 pending 清除。
- 同一 token 可用于 REST Bearer 与 WS `AuthReq`（双通道一致）。

---

## 禁止

- 用户名密码出现在 WebSocket URL 或 `AuthReq` 以外的字段。
- 封禁后仍接受该 `device_id` 的新 token（须先解封 `banned_at`）。
