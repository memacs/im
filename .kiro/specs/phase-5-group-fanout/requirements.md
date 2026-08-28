# Requirements: Phase 5 群聊与扇出

| Spec | `phase-5-group-fanout` |
| Roadmap | P5-01 ~ P5-12 |

## 本切片（P5-01 / P5-02）

1. WHEN `ChatMessage.chat_type = CHAT_GROUP`，THE SYSTEM SHALL 校验发送方为群成员，并将 `conv_id` 规范为 `g:{group_id}`（`to` = `group_id`）。
2. WHEN 群消息发送成功，THE SYSTEM SHALL 写入 1 行 `message_bodies` 与写扩散模式下全体成员的 `user_inbox`。
3. WHEN 成员在线，THE SYSTEM SHALL 向其设备 `CMD_MSG_PUSH`（发送设备排除）。
4. WHEN 成员离线后上线，THE SYSTEM SHALL 能通过既有 `OFFLINE_PULL` JOIN 拉取群消息。

## 后续切片（本 Spec 覆盖，实现分步）

5. WHEN 节点数 >1，THE SYSTEM SHALL 经 Tracker/树状扇出定位在线连接（P5-03–06）。
6. WHEN `target_users` 非空，THE SYSTEM SHALL 仅对目标∪发送方写 inbox 与推送（P5-07）。
