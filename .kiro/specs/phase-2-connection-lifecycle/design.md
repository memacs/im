# Design: Phase 2 连接生命周期

| 项 | 内容 |
| --- | --- |
| Spec | `phase-2-connection-lifecycle` |
| requirements | [requirements.md](./requirements.md) |

---

## Architecture

```text
HTTP POST /api/v1/sessions
  → SessionController → Services.Session → AccessTokenStore / UserDeviceStore
  → JSON {access_token, connection, config, clear_local_data}

WS GET /ws  (WebSockAdapter → IMWeb.PacketTransport)
  → Codec.decode → ConnectionState.allow?
  → Handler → Commands.* → Dispatch → Services.*
  → Reply/Push → Codec.encode → {:binary, frame}
```

**不用** Phoenix Channel 帧；客户端直连二进制 `Packet`。

---

## Components

| 模块 | 路径 |
|------|------|
| Migration | `priv/repo/migrations/*_auth_tables.exs`：`users`(+password_hash)、`user_devices`、`access_tokens` |
| Schemas | `lib/im/schemas/{user,user_device,access_token}.ex` |
| Stores | `lib/im/stores/{access_token_store,user_device_store,user_store}.ex` |
| Session | `lib/im/services/session.ex` |
| Auth Behaviour | `lib/im/auth.ex` + `lib/im/auth/token_verifier.ex` |
| Auth Service | `lib/im/services/auth.ex` |
| Heartbeat | `lib/im/services/heartbeat.ex`（薄） |
| Kick / DeviceBan / DeviceLimit | `lib/im/services/{kick,device_ban,device_limit}.ex` |
| Registry | `lib/im/connection/registry.ex`（Registry） |
| Dispatch | `lib/im/application/dispatch.ex` |
| ConnectionState | `lib/im/websocket/connection_state.ex`（三态） |
| Handler | `lib/im/websocket/handler.ex` |
| Commands | `lib/im/websocket/commands/{auth,heartbeat}.ex` |
| PacketTransport | `lib/im_web/packet_transport.ex`（WebSock） |
| Controllers | `lib/im_web/controllers/api/v1/{session,device}_controller.ex` |
| Plugs | `lib/im_web/plugs/{bearer_auth,require_trace_id}.ex` |
| Fallback | `lib/im_web/controllers/fallback_controller.ex` |
| Telemetry | `lib/im/telemetry/websocket.ex` |
| Log | 增强 `lib/im/log.ex` |

---

## Key Algorithms

### Token

- 明文：`Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)`
- 存储：`Base.encode16(:crypto.hash(:sha256, token), case: :lower)`
- TTL：默认 86400s（`config :im, :token_ttl_sec`）
- 校验：revoked → expires → device banned

### Password（MVP）

- `users.password_hash` = SHA-256 hex(`password <> ":" <> app_key <> ":" <> user_id`)
- 无新 hex 依赖；后续可换 bcrypt Behaviour

### ConnectionState.allow?/2

见 impl `auth.md` §2.2：`:ok | {:error, :silent_close | :already_authenticated | :invalid_cmd}`

### DeviceLimit

- 默认每平台上限 5；策略默认 `kick_oldest_on_platform`
- 配置：`config :im, :device_limit`（租户 app_configs 后续接）

---

## Testing

| 文件 | 覆盖 |
|------|------|
| `test/im/services/session_test.exs` | 登录/错密/封禁/吊销 |
| `test/im/services/auth_test.exs` | token 校验 |
| `test/im/websocket/connection_state_test.exs` | 允许矩阵 |
| `test/im_web/packet_transport_test.exs` | AUTH→HB 黄金路径（进程内） |
| `test/im_web/controllers/api/v1/session_controller_test.exs` | HTTP |
| `test/im/services/device_ban_test.exs` / `kick_test.exs` / `device_limit_test.exs` | 封禁踢人限制 |

---

## Config

```elixir
config :im,
  token_ttl_sec: 86_400,
  websocket_urls: ["ws://localhost:4000/ws"],
  auth_timeout_ms: 10_000,
  idle_timeout_ms: 90_000,
  device_limit: %{max_per_platform: 5, policy: :kick_oldest_on_platform}
```
