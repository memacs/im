# Requirements: im_client C0/C1

| 项 | 内容 |
| --- | --- |
| Spec | `im-client-c0-c1` |
| Roadmap | IC-01 ~ IC-05、IC-08、IC-10（压测所需最小集） |
| 权威 | `proto/`、`docs/design/test-client.md`、PROGRESS im_client 轨道 |
| 状态 | 实施中 |

---

## Introduction

交付共享库 `apps/elixir/im_client`：与 `im` 一致的 Packet Codec、WebSocket 连接状态机、AUTH/心跳、Inbox 等待、REST 登录与最小 `send_message`，供 `loadtest` 与后续 `im` ExUnit 复用。**不**打进 IM Release。

---

## User Stories

### US-1：项目与 Codec

**作为** 压测/集成测试作者，**我想** 在独立 Mix 项目中编解码 `Packet`，**以便** 不依赖完整 `im` 应用即可构造协议帧。

#### Acceptance Criteria

1. WHEN 执行 `mix compile`（`apps/elixir/im_client`），THE SYSTEM SHALL 编译通过。
2. WHEN 编解码 `ver = 1` 的合法 Packet，THE SYSTEM SHALL round-trip 关键字段一致。
3. WHEN `ver ≠ 1` 或帧损坏，THE SYSTEM SHALL 返回 `{:error, %IM.Client.Error{}}` 且不崩溃。
4. THE SYSTEM SHALL 使用与 `im` 同源的 `Pb.Im.Protocol.*`（由 `mise run proto-gen` 同步）。

### US-2：连接与鉴权

**作为** 自动化客户端，**我想** 连接 `/ws` 并完成 AUTH / HEARTBEAT / disconnect，**以便** 建立可用会话。

#### Acceptance Criteria

1. WHEN `connect/1` 成功，THE SYSTEM SHALL 状态为 `:connected`（未鉴权）。
2. WHEN `authenticate/2` 收到 `CMD_AUTH_RESP`，THE SYSTEM SHALL 状态为 `:authenticated`。
3. WHEN `heartbeat/1` 在已鉴权状态发出，THE SYSTEM SHALL 能等到 `CMD_HEARTBEAT_RESP`（同 `seq`）。
4. WHEN `disconnect/1`，THE SYSTEM SHALL 关闭传输并进入 `:disconnected`。

### US-3：Inbox 与 REST / 发消息（压测最小）

1. WHEN 调用方按 `seq` 或 `cmd` 等待，THE SYSTEM SHALL 在超时前返回匹配 Packet 或 `{:error, :timeout}`。
2. WHEN `IM.Client.REST.create_session/2`，THE SYSTEM SHALL `POST /api/v1/sessions`（含 `X-Trace-Id`）并解析 `access_token` / `websocket_urls`。
3. WHEN `send_message/2`，THE SYSTEM SHALL 发送 `CMD_MSG_SEND` 并同步等待 `CMD_MSG_ACK_DOWN`（同 `seq`）。
