# Design：Wave 1

| 项 | 方案 |
| --- | --- |
| MsgId 租约 | `IM.Services.MsgId.Lease`：`SET im:id:worker:{id} NX EX 30`；10s 续期；PG `id_workers` |
| Cache 扩展 | `set_nx/3`、`del/1`（Memory + Redis） |
| Encoder | 默认 `:protobuf`；可选 `:json_envelope` |
| push_token | `PUT /api/v1/devices/:device_id/push-token` → UserDeviceStore |
| loadtest | 解码 CreateResp；`CHAT_GROUP` / `CHAT_ROOM` + 正确 id |
