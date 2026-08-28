# Requirements: Phase 4 离线拉取

| Spec | `phase-4-offline-pull` |
| Roadmap | P4-01 ~ P4-05 |

1. WHEN `CMD_OFFLINE_PULL_REQ` 无 `conv_id`，THE SYSTEM SHALL 按 `inbox_seq` 增量拉取 JOIN bodies，默认 limit 50、上限 200，返回 `has_more`。
2. WHEN 带 `conv_id`，THE SYSTEM SHALL 按该会话 `conv_seq` 拉取。
3. WHEN AUTH 后客户端拉取，THE SYSTEM SHALL 允许已鉴权连接发送 OFFLINE_PULL。
4. THE SYSTEM SHALL 以 `(app_key, user_id)` 为 inbox 分片键（表 PK 已体现）。
