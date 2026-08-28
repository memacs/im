# Requirements: P7-08 MSG_STREAM 落库 + P8-09 须好友才能单聊

| 项 | 内容 |
| --- | --- |
| Spec | `p7-08-p8-09` |
| Roadmap | P7-08、P8-09 |
| 权威 | `proto/message.proto`、`docs/design/stream-message.md`、`docs/design/friend.md` |

## P7-08

1. WHEN 客户端以 `msg_type=MSG_STREAM` 且 `content=StreamContent` 发送，THE SYSTEM SHALL 校验 `stream_id`/`status`/`sequence` 后落库（`message_bodies.msg_type=8`）。
2. WHEN 离线拉取含流式消息，THE SYSTEM SHALL 返回正确 `msg_type` 与原始 `content`。
3. THE SYSTEM SHALL 提供 `StreamManager` 跟踪同一 `stream_id` 的块顺序，拒绝已结束流上的后续 ONGOING。

## P8-09

1. THE SYSTEM SHALL 默认**不**强制好友即可单聊。
2. WHEN `app_configs` 中 `friend.require_friend_to_send=true`，且双方非 `accepted` 好友，THE SYSTEM SHALL 拒绝单聊发送并返回 `CODE_FRIEND_NOT_FRIEND`（7006）。
3. 拉黑检查优先于好友门禁（语义不变）。
