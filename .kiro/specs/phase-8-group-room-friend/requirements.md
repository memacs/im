# Requirements: Phase 8 群 / 室 / 好友管理

| Spec | `phase-8-group-room-friend` |
| Roadmap | P8-01 ~ P8-09（P8-09 **done**：`require_friend_to_send`） |

1. WHEN `CMD_GROUP_CREATE_REQ` 成功，THE SYSTEM SHALL 返回 `CMD_GROUP_CREATE_RESP`（含 `group_id`/`conv_id`），并向初始成员推送 `CMD_GROUP_JOIN_PUSH`。
2. WHEN 解散/加入/退群/踢人/邀请成功，THE SYSTEM SHALL 以对应 `CMD_GROUP_*_PUSH` 回传操作者 `seq`，并向相关在线成员广播（`seq=0`）。
3. THE SYSTEM SHALL 按权限矩阵校验：仅群主可解散/设管/转让；管理员可踢普通成员与邀请/更新。
4. WHEN `CMD_ROOM_DISMISS/KICK/UPDATE` 成功，THE SYSTEM SHALL 更新持久化并与 `Room.PubSub` 生命周期联动。
5. WHEN 好友添加/接受/拒绝/删除/拉黑成功，THE SYSTEM SHALL 落库并推送对应 `CMD_FRIEND_*` 通知。
6. WHEN 用户已被对方拉黑，THE SYSTEM SHALL 拒绝单聊 `CMD_MSG_SEND`（P8-08）。
7. P8-09「须为好友才能单聊」：`app_configs.friend.require_friend_to_send`（默认 false）。
