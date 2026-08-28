# Design: P7-08 / P8-09

## P7-08 MSG_STREAM

```
CMD_MSG_SEND (MSG_STREAM)
  → Message.validate（decode StreamContent）
  → StreamManager.track_chunk
  → MessageStore 落库（每块一条）
  → Offline.pull 还原 msg_type=MSG_STREAM
```

`content` 存 `StreamContent` protobuf 字节；方案一（每块独立存储）。

## P8-09 须好友

```
app_configs (category=friend, key=require_friend_to_send)
  → AppConfigStore.get_boolean
  → Friend.check_send_permission
  → Message.validate_private
```

默认 false；测试用 `AppConfigStore.put/4` 开启。
