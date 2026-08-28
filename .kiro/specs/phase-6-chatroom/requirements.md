# Requirements: Phase 6 聊天室

| Spec | `phase-6-chatroom` |
| Roadmap | P6-01 ~ P6-06 |

1. WHEN `CMD_ROOM_JOIN_REQ` 成功，THE SYSTEM SHALL 将连接 subscribe 到 `room:{app_key}:{room_id}`，并可收后续广播。
2. WHEN `CHAT_ROOM` 消息发送，THE SYSTEM SHALL 预编码一次后 `PubSub.broadcast`（不调用 GroupPusher）。
3. WHEN 广播到达连接，THE SYSTEM SHALL 排除发送设备，并投递给发送方其他设备。
4. THE SYSTEM SHALL 默认不将聊天室消息写入 `user_inbox` / OFFLINE_PULL。
5. THE SYSTEM SHALL 仅要求 `SERVER_RECEIVED` ACK。
6. WHEN `target_users` 非空，THE SYSTEM SHALL 仅向目标∪发送方设备投递。
