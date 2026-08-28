# Design: Phase 6 聊天室

```text
ROOM_JOIN → RoomStore.add_member → PubSub.subscribe(room:app:room)
MSG_SEND(CHAT_ROOM) → ACK SERVER_RECEIVED → encode once → PubSub.broadcast
PacketTransport ← {:im_room_push, bin, meta} → filter exclude/target → WS push
```

| Module | Role |
|--------|------|
| `IM.Stores.RoomStore` | rooms / room_members |
| `IM.Services.Room` | create/join/leave |
| `IM.Room.PubSub` | topic + broadcast helpers |
| `Commands.RoomJoin/Leave/Create` | WS |
| `Message` | CHAT_ROOM validate + no inbox |
