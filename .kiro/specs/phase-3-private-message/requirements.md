# Requirements: Phase 3 单聊消息主路径

| Spec | `phase-3-private-message` |
| Roadmap | P3-01 ~ P3-12 |
| 依赖 | Phase 2 |

## Acceptance (EARS)

1. WHEN `CMD_MSG_SEND` 且 `chat_type=CHAT_PRIVATE`、`conv_id` 与 `p:lo:hi` 一致（空则回填），THE SYSTEM SHALL 同步落库后回 `ACK_DOWN(SERVER_RECEIVED)`（同 seq）。
2. WHEN `conv_id` 非法或非单聊，THE SYSTEM SHALL `CODE_MSG_INVALID`，不关连接。
3. WHEN 同 `(app_key,from,client_msg_id)` 重复 SEND，THE SYSTEM SHALL 返回同一 `msg_id`/`conv_seq`，不重复写库、不重复 PUSH。
4. WHEN 同连接同 `Packet.cid` 短窗重复，THE SYSTEM SHALL 网关去重（与业务幂等分层）。
5. WHEN SEND 成功，THE SYSTEM SHALL 向对端及发送方其他设备 `CMD_MSG_PUSH`（`seq=0`）；发送设备不收。
6. WHEN 接收方 `ACK_UP(CLIENT_RECEIVED)`，THE SYSTEM SHALL 向发送方 `ACK_DOWN(CLIENT_RECEIVED, seq=0)`。
7. WHEN REST `POST /api/v1/messages`，THE SYSTEM SHALL 经 Dispatch 走同一 `IM.Services.Message`。
8. THE SYSTEM SHALL 用 Snowflake（或 PG 兜底）生成 `msg_id`；`conv_seq`/`inbox_seq` 服务端单调分配。
9. THE SYSTEM SHALL 在 SEND 路径同步执行 Pre-Hook（默认 no-op），不得 async 后再 ACK。
