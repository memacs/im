# Design: Phase 3 单聊消息

## Flow

```text
MSG_SEND → validate → cid dedup → PreHook → idempotent insert
  → ACK_DOWN(SERVER_RECEIVED) → Delivery PUSH (peer + other devices)
ACK_UP → ACK_DOWN(CLIENT_RECEIVED) to sender devices
```

## Modules

| Module | Role |
|--------|------|
| `IM.Services.Message` | send / ack_up |
| `IM.Services.MsgId` | Snowflake GenServer + PG fallback |
| `IM.Services.Sequence` | PG `msg_sequences` INCR |
| `IM.Stores.MessageStore` | bodies + inbox |
| `IM.Gateway.CidDedup` | ETS per session_id+cid |
| `IM.Hooks.PreSend` | default :ok |
| `IM.Delivery.Router` | Registry push binary |
| `IM.Delivery.Outbound` | priority sort helper (WFQ MVP) |
| `Commands.MsgSend` / `MsgAck` | WS thin |
| `Api.V1.MessageController` | REST |

## Seq / ID without Redis (MVP)

- `conv_seq` / `inbox_seq` / `msg_id_fallback` → PG upsert
- Snowflake worker_id → `:erlang.phash2(node(), 1024)` + GenServer ms sequence
- Redis 接入延后 Phase 9

## conv_id

`p:{min(uid1,uid2)}:{max(uid1,uid2)}` 字典序
