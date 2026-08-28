# Requirements: Phase 7 消息扩展命令

| Spec | `phase-7-message-extensions` |
| Roadmap | P7-01 ~ P7-10（P7-08 **done**） |

1. WHEN `CMD_MSG_ACK_BATCH_UP`，THE SYSTEM SHALL 将各条转为 `CLIENT_RECEIVED` 并 `ACK_BATCH_DOWN` 给发送方。
2. WHEN `CMD_MSG_READ`，THE SYSTEM SHALL 向会话对端/相关方推送已读，并在覆盖阅后即焚消息时调度销毁。
3. WHEN `CMD_MSG_RECALL_REQ` 在 `recall_window_sec` 内，THE SYSTEM SHALL 标记 `recalled` 并 `RECALL_PUSH`。
4. WHEN `CMD_MSG_EDIT_REQ` 在窗内，THE SYSTEM SHALL 更新 content、`edit_version++` 并 `EDIT_PUSH`。
5. WHEN `burn_after_read` 单聊消息被对端已读覆盖，THE SYSTEM SHALL 清空 content 并 `BURN_PUSH`。
6. WHEN `CMD_PASSTHROUGH`，THE SYSTEM SHALL 实时推送；`persist=true` 时写入 `passthrough_messages`（不进 OFFLINE_PULL）。
7. WHEN 流式透传 `action` 为 stream_start/chunk/end，THE SYSTEM SHALL 按 PASSTHROUGH 路径转发。
8. THE SYSTEM SHALL 提供 TTL 清理 Job：分批删除过期 chat/room/passthrough 数据。
