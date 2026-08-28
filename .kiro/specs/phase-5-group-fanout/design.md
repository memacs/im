# Design: Phase 5 群聊扇出

## MVP（P5-01/02）

```text
MSG_SEND(CHAT_GROUP) → member check → allocate msg_id/conv_seq
  → insert body + N inbox (write_fanout)
  → ACK_DOWN → Registry push each member (exclude sender device)
```

| Module | Role |
|--------|------|
| `IM.Stores.GroupStore` | groups / group_members |
| `IM.Services.Group` | create + list members |
| `IM.Services.Message` | validate_group + send |
| `IM.Domain.ConvId` | `g:{group_id}` |
| `Api.V1.GroupController` | 最小建群 REST |

## Deferred

Tracker、树状扇出、Oban 异步 inbox、Redis 成员缓存、`target_users`、`read_fanout`、`PUSH_BATCH`。
