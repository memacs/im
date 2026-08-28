# HTTP API 参考（逐接口）

| 项 | 内容 |
| --- | --- |
| 路由定义 | `apps/elixir/im/lib/im_web/router.ex` |
| 设计约定 | [dual-channel-api.md](../../design/dual-channel-api.md) |
| 实现说明 | [dual-channel-api.md](dual-channel-api.md)（Dispatch / Plug） |
| 测试示例 | `apps/elixir/im/test/im_web/controllers/api/v1/dual_channel_rest_test.exs` |

本文档列出 **当前已实现** 的全部 HTTP 端点，含请求头、JSON 参数与响应示例。WebSocket 二进制协议见 [protocol.md](../../design/protocol/protocol.md)。

**Base URL**（本地开发）：`http://localhost:4000`

---

## 1. 公共约定

### 1.1 请求头

| 头 | 适用 | 必填 | 说明 |
| --- | --- | --- | --- |
| `X-Trace-Id` | 全部 `/api/v1`、`/internal/v1` | **是** | 链路追踪 ID，建议 UUID 或业务可关联字符串 |
| `Authorization: Bearer <token>` | `/api/v1`（除登录） | **是** | 登录返回的 `access_token` |
| `Content-Type: application/json` | 带 body 的 POST/PATCH/PUT | 推荐 | JSON 请求体 |
| `X-IM-Caller-Service` | `/internal/v1` | **是** | 调用方服务名，如 `user-service`、`loadtest` |

### 1.2 错误响应

业务失败时返回 JSON（与 WS `ErrorBody` 语义对齐）：

```json
{
  "code": 1001,
  "msg": "unauthorized",
  "ref_cmd": 101,
  "ref_cid": ""
}
```

| HTTP 状态 | 常见 `code` / `msg` |
| --- | --- |
| `400` | 参数非法、`missing_trace_id` |
| `401` | token 无效 / 过期 |
| `403` | 无权限、设备封禁、好友拉黑 |
| `404` | 群/资源不存在 |
| `429` | 频控 |
| `500` | 内部错误 |

成功且无 body 时部分接口返回 **`204 No Content`**。

### 1.3 通用类型

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `chat_type` | string | `CHAT_PRIVATE`（默认）、`CHAT_GROUP` / `group` / `2`、`CHAT_ROOM` / `room` / `3` |
| 时间戳 | int64 | 毫秒 Unix 时间 |
| `conv_id` | string | 会话 ID，如 `p:alice:bob`、`g:group123`、`r:room456` |

---

## 2. 健康与指标（无需鉴权）

### `GET /health/live`

存活探针，不检查依赖。

**响应 `200`**

```json
{ "status": "ok" }
```

### `GET /health/ready`

就绪探针，检查数据库。

**响应 `200`**

```json
{ "status": "ok", "database": "connected" }
```

**响应 `503`**

```json
{ "status": "error", "database": "..." }
```

### `GET /health`

同 `/health/live`。

### `GET /metrics`

Prometheus 文本格式指标（无需 `X-Trace-Id`）。

---

## 3. 客户端 API（`/api/v1`）

以下接口均需 **`X-Trace-Id`**；除登录外均需 **`Authorization: Bearer <access_token>`**。

---

### 3.1 会话

#### `POST /api/v1/sessions` — 登录

**鉴权**：无 Bearer（仅需 `X-Trace-Id`）

**请求体**

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `app_key` | 是 | 应用标识 |
| `user_id` | 是 | 用户 ID |
| `password` | 是 | 密码 |
| `device_id` | 是 | 设备唯一 ID |
| `platform` | 否 | 如 `ios`、`android`、`web` |
| `sdk_ver` | 否 | SDK 版本 |

**示例**

```bash
curl -sS -X POST http://localhost:4000/api/v1/sessions \
  -H 'X-Trace-Id: login-001' \
  -H 'Content-Type: application/json' \
  -d '{
    "app_key": "demo",
    "user_id": "alice",
    "password": "secret",
    "device_id": "dev-alice-1",
    "platform": "web"
  }'
```

**响应 `200`**

```json
{
  "access_token": "eyJ...",
  "expires_at": 1754300000000,
  "user_id": "alice",
  "clear_local_data": false,
  "connection": {
    "websocket_urls": ["ws://localhost:4000/ws"],
    "preferred_index": 0
  },
  "config": {}
}
```

**响应 `403`**（设备封禁）

```json
{ "code": 1001, "msg": "device_banned" }
```

---

#### `DELETE /api/v1/sessions/current` — 登出

吊销当前 Bearer token。

**响应 `204`**（无 body）

```bash
curl -sS -X DELETE http://localhost:4000/api/v1/sessions/current \
  -H 'X-Trace-Id: logout-001' \
  -H 'Authorization: Bearer <access_token>'
```

---

### 3.2 设备

路径中的 `:device_id` **必须**与 token 内 `device_id` 一致。

#### `POST /api/v1/devices/:device_id/local-data-cleared`

客户端完成「清本地数据」后上报。

**响应 `204`**

```bash
curl -sS -X POST http://localhost:4000/api/v1/devices/dev-alice-1/local-data-cleared \
  -H 'X-Trace-Id: clear-001' \
  -H 'Authorization: Bearer <access_token>'
```

#### `PUT /api/v1/devices/:device_id/push-token` — 注册推送 Token

**请求体**

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `push_token` | 是 | FCM/APNs 等设备 token |

**示例**

```bash
curl -sS -X PUT http://localhost:4000/api/v1/devices/dev-alice-1/push-token \
  -H 'X-Trace-Id: push-001' \
  -H 'Authorization: Bearer <access_token>' \
  -H 'Content-Type: application/json' \
  -d '{ "push_token": "fcm-token-xxx" }'
```

**响应 `200`**

```json
{
  "device_id": "dev-alice-1",
  "push_token_registered": true
}
```

#### `POST /api/v1/devices/:device_id/ban` — 封禁设备（MVP）

**请求体**

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `reason` | 否 | 默认 `admin` |
| `clear_local_data` | 否 | `true` 时下发行清数据指令 |

**响应 `204`**

---

### 3.3 消息

#### `POST /api/v1/messages` — 发送消息

**请求体**

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `to` | 是 | 接收方 user_id / group_id / room_id |
| `content` | 是 | 文本内容 |
| `client_msg_id` | 推荐 | 客户端去重 ID |
| `chat_type` | 否 | 默认私聊 `CHAT_PRIVATE` |
| `conv_id` | 否 | 不传则由服务端推导 |
| `from` | 否 | 默认当前用户 |
| `target_users` | 否 | 群 @ 指定用户 UID 列表 |
| `burn_after_read` | 否 | 阅后即焚 |

**示例（私聊）**

```bash
curl -sS -X POST http://localhost:4000/api/v1/messages \
  -H 'X-Trace-Id: msg-001' \
  -H 'Authorization: Bearer <access_token>' \
  -H 'Content-Type: application/json' \
  -d '{
    "to": "bob",
    "content": "hello",
    "client_msg_id": "cm-1001"
  }'
```

**响应 `200`**

```json
{
  "msg_id": "m_abc123",
  "client_msg_id": "cm-1001",
  "conv_id": "p:alice:bob",
  "conv_seq": 1,
  "server_time": 1754300000123,
  "status": "SERVER_RECEIVED",
  "duplicate": false
}
```

---

#### `GET /api/v1/messages/inbox` — 离线收件箱拉取

**Query**

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| `cursor` | `0` | 分页游标（inbox_seq） |
| `limit` | `50` | 条数上限 |

```bash
curl -sS 'http://localhost:4000/api/v1/messages/inbox?cursor=0&limit=50' \
  -H 'X-Trace-Id: inbox-001' \
  -H 'Authorization: Bearer <access_token>'
```

**响应 `200`**

```json
{
  "messages": [
    {
      "msg_id": "m_abc123",
      "client_msg_id": "cm-1001",
      "chat_type": "CHAT_PRIVATE",
      "from": "alice",
      "to": "bob",
      "conv_id": "p:alice:bob",
      "content": "hello",
      "server_time": 1754300000123,
      "conv_seq": 1,
      "inbox_seq": 42
    }
  ],
  "next_cursor": 42,
  "has_more": false
}
```

---

#### `GET /api/v1/conversations/:conv_id/messages` — 按会话拉取

Query 同 inbox（`cursor`、`limit`）。

```bash
curl -sS 'http://localhost:4000/api/v1/conversations/p:alice:bob/messages?limit=20' \
  -H 'X-Trace-Id: conv-msg-001' \
  -H 'Authorization: Bearer <access_token>'
```

响应格式同 inbox。

---

#### `POST /api/v1/messages/ack` — 单条 ACK

**请求体**

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `msg_id` | 是 | 消息 ID |
| `client_msg_id` | 否 | 客户端消息 ID |
| `conv_seq` | 否 | 会话序号 |

```bash
curl -sS -X POST http://localhost:4000/api/v1/messages/ack \
  -H 'X-Trace-Id: ack-001' \
  -H 'Authorization: Bearer <access_token>' \
  -H 'Content-Type: application/json' \
  -d '{ "msg_id": "m_abc123", "conv_seq": 1 }'
```

**响应 `200`**（ACK 下行结构，字段随协议）

```json
{ "msg_id": "m_abc123", "status": "CLIENT_RECEIVED" }
```

---

#### `POST /api/v1/messages/ack-batch` — 批量 ACK

**请求体**

```json
{
  "acks": [
    { "msg_id": "m_1", "conv_seq": 1 },
    { "msg_id": "m_2", "conv_seq": 2 }
  ]
}
```

**响应 `200`**

```json
{
  "batches": [
    {
      "sender_user_id": "alice",
      "acks": "[{\"msg_id\":\"m_1\",...}]"
    }
  ]
}
```

---

#### `POST /api/v1/messages/read` — 已读回执

**请求体**

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `conv_id` | 是 | 会话 ID |
| `to` | 是 | 对端 user_id / group_id |
| `msg_id` | 否 | 已读到的消息 ID |
| `conv_seq` | 否 | 已读会话序号 |
| `chat_type` | 否 | 默认私聊 |

```bash
curl -sS -X POST http://localhost:4000/api/v1/messages/read \
  -H 'X-Trace-Id: read-001' \
  -H 'Authorization: Bearer <access_token>' \
  -H 'Content-Type: application/json' \
  -d '{
    "conv_id": "p:alice:bob",
    "to": "alice",
    "conv_seq": 1,
    "chat_type": "CHAT_PRIVATE"
  }'
```

---

#### `POST /api/v1/messages/:msg_id/recall` — 撤回

**请求体**

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `conv_id` | 推荐 | 会话 ID |
| `reason` | 否 | 撤回原因 |

```bash
curl -sS -X POST http://localhost:4000/api/v1/messages/m_abc123/recall \
  -H 'X-Trace-Id: recall-001' \
  -H 'Authorization: Bearer <access_token>' \
  -H 'Content-Type: application/json' \
  -d '{ "conv_id": "p:alice:bob" }'
```

**响应 `200`**

```json
{ "msg_id": "m_abc123", "recalled": true }
```

---

#### `POST /api/v1/messages/:msg_id/edit` — 编辑

**请求体**

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `content` | 是 | 新内容 |
| `conv_id` | 推荐 | 会话 ID |

```bash
curl -sS -X POST http://localhost:4000/api/v1/messages/m_abc123/edit \
  -H 'X-Trace-Id: edit-001' \
  -H 'Authorization: Bearer <access_token>' \
  -H 'Content-Type: application/json' \
  -d '{ "content": "edited text", "conv_id": "p:alice:bob" }'
```

---

### 3.4 会话列表

#### `GET /api/v1/conversations`

**Query**

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| `limit` | `100` | 返回条数 |

```bash
curl -sS 'http://localhost:4000/api/v1/conversations?limit=50' \
  -H 'X-Trace-Id: conv-list-001' \
  -H 'Authorization: Bearer <access_token>'
```

**响应 `200`**

```json
{
  "conversations": [
    {
      "conv_id": "p:alice:bob",
      "chat_type": "CHAT_PRIVATE",
      "peer_id": "bob",
      "last_msg_id": "m_abc123",
      "last_msg_type": "MSG_TEXT",
      "last_msg_preview": "hello",
      "last_msg_time": 1754300000123,
      "last_msg_seq": 1,
      "last_read_conv_seq": 0,
      "unread_count": 1
    }
  ],
  "total_unread": 1
}
```

---

### 3.5 透传

#### `POST /api/v1/passthrough`

**请求体**

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `to` | 是 | 目标 user_id / group_id |
| `action` | 是 | 动作名，如 `typing` |
| `data` / `payload` | 否 | 二进制或 JSON（JSON 会编码） |
| `chat_type` | 否 | 默认私聊 |
| `conv_id` | 否 | 会话 ID |
| `persist` | 否 | 是否持久化 |
| `ttl_sec` | 否 | TTL 秒 |

```bash
curl -sS -X POST http://localhost:4000/api/v1/passthrough \
  -H 'X-Trace-Id: pt-001' \
  -H 'Authorization: Bearer <access_token>' \
  -H 'Content-Type: application/json' \
  -d '{ "to": "bob", "action": "typing", "data": "1" }'
```

**响应 `200`**

```json
{
  "ok": true,
  "to": "bob",
  "action": "typing",
  "chat_type": "CHAT_PRIVATE"
}
```

---

### 3.6 好友

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| `GET` | `/api/v1/friends` | 好友列表 |
| `GET` | `/api/v1/friends/requests` | 待处理申请 |
| `POST` | `/api/v1/friends` | 发起申请 |
| `POST` | `/api/v1/friends/accept` | 接受 |
| `POST` | `/api/v1/friends/reject` | 拒绝 |
| `DELETE` | `/api/v1/friends` | 删除好友 |
| `POST` | `/api/v1/friends/block` | 拉黑 |
| `POST` | `/api/v1/friends/unblock` | 取消拉黑 |
| `PUT` | `/api/v1/friends/remark` | 设置备注 |

#### `POST /api/v1/friends` — 添加好友

```bash
curl -sS -X POST http://localhost:4000/api/v1/friends \
  -H 'X-Trace-Id: friend-add' \
  -H 'Authorization: Bearer <access_token>' \
  -H 'Content-Type: application/json' \
  -d '{
    "to_user_id": "bob",
    "message": "hi",
    "remark": "Bob"
  }'
```

**响应 `200`**

```json
{ "request_id": "fr_xxx", "to_user_id": "bob" }
```

#### `POST /api/v1/friends/accept`

```json
{
  "request_id": "fr_xxx",
  "from_user_id": "alice",
  "remark": "Alice"
}
```

#### `POST /api/v1/friends/reject`

```json
{ "request_id": "fr_xxx" }
```

#### `DELETE /api/v1/friends`

Query 或 body：`friend_user_id` 或 `user_id`

#### `POST /api/v1/friends/block` / `unblock`

```json
{ "user_id": "bob" }
```

#### `PUT /api/v1/friends/remark`

```json
{ "friend_user_id": "bob", "remark": "同事 Bob" }
```

#### `GET /api/v1/friends`

**响应 `200`**

```json
{ "friends": [ { "user_id": "bob", "remark": "Bob" } ] }
```

---

### 3.7 群组

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| `POST` | `/api/v1/groups` | 创建 |
| `POST` | `/api/v1/groups/:group_id/dismiss` | 解散 |
| `POST` | `/api/v1/groups/:group_id/join` | 加入 |
| `POST` | `/api/v1/groups/:group_id/leave` | 退出 |
| `POST` | `/api/v1/groups/:group_id/kick` | 踢人 |
| `POST` | `/api/v1/groups/:group_id/invite` | 邀请 |
| `POST` | `/api/v1/groups/:group_id/admins` | 设管理员 |
| `DELETE` | `/api/v1/groups/:group_id/admins` | 撤管理员 |
| `POST` | `/api/v1/groups/:group_id/transfer` | 转让群主 |
| `POST` | `/api/v1/groups/:group_id/mute` | 禁言成员 |
| `PATCH` | `/api/v1/groups/:group_id` | 更新资料 |

#### `POST /api/v1/groups` — 创建群

```bash
curl -sS -X POST http://localhost:4000/api/v1/groups \
  -H 'X-Trace-Id: g-create' \
  -H 'Authorization: Bearer <access_token>' \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "研发组",
    "member_uids": ["bob", "carol"],
    "announcement": "欢迎",
    "max_members": 200
  }'
```

**响应 `201`**

```json
{
  "group_id": "g_xxx",
  "name": "研发组",
  "conv_id": "g:g_xxx",
  "owner_uid": "alice",
  "member_count": 3,
  "storage_mode": "inbox"
}
```

可选字段：`group_id`（自定义群 ID）

#### `POST /api/v1/groups/:group_id/kick`

```json
{
  "member_uids": ["bob"],
  "reason": "violation"
}
```

#### `POST /api/v1/groups/:group_id/invite`

```json
{ "member_uids": ["dave"] }
```

#### `POST /api/v1/groups/:group_id/admins`

```json
{ "member_uid": "bob" }
```

#### `POST /api/v1/groups/:group_id/transfer`

```json
{ "new_owner_uid": "bob" }
```

#### `POST /api/v1/groups/:group_id/mute`

```json
{
  "member_uid": "bob",
  "muted_until": 1754303600000
}
```

#### `PATCH /api/v1/groups/:group_id`

```json
{
  "name": "新群名",
  "announcement": "公告",
  "max_members": 500
}
```

---

### 3.8 聊天室

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| `POST` | `/api/v1/rooms` | 创建 |
| `POST` | `/api/v1/rooms/:room_id/dismiss` | 解散 |
| `POST` | `/api/v1/rooms/:room_id/join` | 加入 |
| `POST` | `/api/v1/rooms/:room_id/leave` | 离开 |
| `POST` | `/api/v1/rooms/:room_id/kick` | 踢人 |
| `PATCH` | `/api/v1/rooms/:room_id` | 更新 |
| `POST` | `/api/v1/rooms/:room_id/messages` | 室消息 |

#### `POST /api/v1/rooms` — 创建

```bash
curl -sS -X POST http://localhost:4000/api/v1/rooms \
  -H 'X-Trace-Id: r-create' \
  -H 'Authorization: Bearer <access_token>' \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "直播间",
    "max_members": 1000,
    "persist_msg": false,
    "msg_ttl_sec": 3600
  }'
```

**响应 `201`**

```json
{
  "room_id": "r_xxx",
  "name": "直播间",
  "conv_id": "r:r_xxx"
}
```

可选：`room_id`

#### `POST /api/v1/rooms/:room_id/messages` — 发室消息

```json
{
  "content": "大家好",
  "client_msg_id": "rm-001",
  "target_users": ["bob"]
}
```

**响应 `200`**

```json
{
  "msg_id": "m_room_1",
  "client_msg_id": "rm-001",
  "conv_id": "r:r_xxx",
  "conv_seq": 1,
  "server_time": 1754300000123,
  "status": "SERVER_RECEIVED",
  "duplicate": false
}
```

---

### 3.9 应用通道（Channel）

#### `PUT /api/v1/channels/subscriptions` — 订阅

```bash
curl -sS -X PUT http://localhost:4000/api/v1/channels/subscriptions \
  -H 'X-Trace-Id: ch-sub' \
  -H 'Authorization: Bearer <access_token>' \
  -H 'Content-Type: application/json' \
  -d '{ "channel_ids": ["app:orders", "app:notices"] }'
```

**响应 `200`**

```json
{
  "subscribed": ["app:orders"],
  "failed": [
    { "channel_id": "app:notices", "code": 1001, "msg": "not_found" }
  ]
}
```

#### `DELETE /api/v1/channels/subscriptions` — 取消订阅

```json
{ "channel_ids": ["app:orders"] }
```

**响应 `200`**

```json
{ "unsubscribed": ["app:orders"] }
```

#### `POST /api/v1/channels/publish` — 客户端上行事件

```json
{
  "channel_id": "app:orders",
  "content_type": "application/json",
  "payload": { "event": "ping" },
  "client_event_id": "evt-001"
}
```

**响应 `200`**

```json
{
  "channel_id": "app:orders",
  "event_id": "ev_xxx",
  "accepted": true
}
```

被丢弃时：

```json
{ "accepted": false, "dropped": true }
```

---

## 4. 内部 API（`/internal/v1`）

**不校验**终端用户 Bearer；需 **`X-Trace-Id`** + **`X-IM-Caller-Service`**。仅集群内网可达。

**公共请求头示例**

```bash
-H 'X-Trace-Id: internal-001' \
-H 'X-IM-Caller-Service: loadtest' \
-H 'Content-Type: application/json'
```

---

### 4.1 用户

#### `POST /internal/v1/users/:user_id/provision` — 预置用户

压测 / 冒烟用，幂等插入或更新密码。

**请求体**

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `app_key` | 是 | 应用 |
| `password` | 是 | 明文密码（服务端哈希存储） |
| `nickname` | 否 | 默认等于 `user_id` |

```bash
curl -sS -X POST http://localhost:4000/internal/v1/users/alice/provision \
  -H 'X-Trace-Id: prov-001' \
  -H 'X-IM-Caller-Service: loadtest' \
  -H 'Content-Type: application/json' \
  -d '{
    "app_key": "demo",
    "password": "secret",
    "nickname": "Alice"
  }'
```

**响应 `200`**

```json
{
  "user_id": "alice",
  "app_key": "demo",
  "provisioned": true,
  "caller_service": "loadtest"
}
```

---

#### `POST /internal/v1/users/:user_id/kick` — 踢用户全部设备

**请求体**

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `app_key` | 是 | 应用 |
| `reason` | 否 | 默认 `admin_kick` |
| `clear_local_data` | 否 | 是否清本地数据 |

```json
{
  "app_key": "demo",
  "reason": "risk",
  "clear_local_data": true
}
```

**响应 `200`**

```json
{
  "ok": true,
  "user_id": "alice",
  "caller_service": "loadtest"
}
```

---

#### `POST /internal/v1/users/:user_id/messages` — 服务端代发

**请求体**

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `app_key` | 是 | 应用 |
| `to` | 是 | 接收方 |
| `content` | 是 | 文本 |
| `client_msg_id` | 否 | 去重 ID |
| `device_id` | 否 | 默认 `internal` |
| `run_hooks` | 否 | 默认 `true`，设为 `false` 跳过 Hook |

```json
{
  "app_key": "demo",
  "to": "bob",
  "content": "系统通知",
  "client_msg_id": "sys-001"
}
```

**响应 `200`**

```json
{
  "msg_id": "m_sys_1",
  "client_msg_id": "sys-001",
  "conv_id": "p:alice:bob",
  "status": "SERVER_RECEIVED",
  "duplicate": false,
  "caller_service": "loadtest",
  "source": "http_internal"
}
```

---

### 4.2 设备

#### `POST /internal/v1/devices/:device_id/kick`

**请求体**：`app_key`、`user_id` 必填；可选 `reason`、`clear_local_data`

**响应 `200`**

```json
{ "ok": true, "device_id": "dev-alice-1" }
```

#### `POST /internal/v1/devices/:device_id/ban`

**请求体**：`app_key`、`user_id` 必填；可选 `reason`（默认 `banned`）、`clear_local_data`

**响应 `200`**

```json
{ "ok": true, "device_id": "dev-alice-1", "banned": true }
```

---

### 4.3 通道下行广播

#### `POST /internal/v1/channels/:namespace/:name/publish`

路径 `:namespace` + `:name` 组成 `channel_id`（如 `app` + `orders` → `app:orders`）。

**请求体**

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `app_key` | 推荐 | 应用隔离 |
| `content_type` | 否 | 默认 `application/json` |
| `payload` | 是 | 任意 JSON 或可序列化结构 |

```bash
curl -sS -X POST http://localhost:4000/internal/v1/channels/app/orders/publish \
  -H 'X-Trace-Id: ch-pub-001' \
  -H 'X-IM-Caller-Service: order-service' \
  -H 'Content-Type: application/json' \
  -d '{
    "app_key": "demo",
    "payload": { "order_id": "O123", "status": "shipped" }
  }'
```

**响应 `200`**

```json
{
  "event_id": "ev_down_1",
  "channel_id": "app:orders",
  "accepted": true
}
```

---

## 5. 端点速查表

### 客户端 `/api/v1`

| 方法 | 路径 | 鉴权 |
| --- | --- | --- |
| `POST` | `/sessions` | TraceId |
| `DELETE` | `/sessions/current` | Bearer |
| `POST` | `/devices/:id/local-data-cleared` | Bearer |
| `PUT` | `/devices/:id/push-token` | Bearer |
| `POST` | `/devices/:id/ban` | Bearer |
| `POST` | `/messages` | Bearer |
| `GET` | `/messages/inbox` | Bearer |
| `GET` | `/conversations/:conv_id/messages` | Bearer |
| `GET` | `/conversations` | Bearer |
| `POST` | `/messages/ack` | Bearer |
| `POST` | `/messages/ack-batch` | Bearer |
| `POST` | `/messages/read` | Bearer |
| `POST` | `/messages/:msg_id/recall` | Bearer |
| `POST` | `/messages/:msg_id/edit` | Bearer |
| `POST` | `/passthrough` | Bearer |
| `GET/POST/DELETE/PUT` | `/friends/*` | Bearer |
| `POST/PATCH/DELETE` | `/groups/*` | Bearer |
| `POST/PATCH` | `/rooms/*` | Bearer |
| `PUT/DELETE/POST` | `/channels/*` | Bearer |

### 内部 `/internal/v1`

| 方法 | 路径 |
| --- | --- |
| `POST` | `/users/:user_id/provision` |
| `POST` | `/users/:user_id/kick` |
| `POST` | `/users/:user_id/messages` |
| `POST` | `/devices/:device_id/kick` |
| `POST` | `/devices/:device_id/ban` |
| `POST` | `/channels/:namespace/:name/publish` |

### 运维（无 TraceId）

| 方法 | 路径 |
| --- | --- |
| `GET` | `/health/live`、`/health/ready`、`/health` |
| `GET` | `/metrics` |
| `GET` | `/ws`（WebSocket 升级，非 REST） |

---

## 6. 与 WebSocket 的关系

同一业务经 `IM.Application.Dispatch` 执行，REST 与 WS **语义一致**。REST 适合：

- 登录拿 token、离线拉取、管理类操作
- 无长连接场景（推送仍走 WS / 移动推送）

长连接实时收发仍推荐 WebSocket；详见 [dual-channel-api.md](../../design/dual-channel-api.md)。
