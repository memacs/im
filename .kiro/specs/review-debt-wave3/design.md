# Design — Review Debt Wave3

## Cache Behaviour 扩展

```text
IM.Cache
  ├── sadd / srem / sismember
  ├── zadd / zrem / zscore
  └── exists?
Memory：ETS 值可为 {:set, MapSet} | {:zset, %{member => score}}
Redis：对应 SISMEMBER / ZSCORE 等命令
```

冷 key：`exists?` 为 false 时回源；空集合也写 loaded 标记（block/mute 在写穿或 warm 后保证 key 存在——Memory 存空 set/zset；Redis 对空列表用 companion `*:loaded` STRING，或 warm 后仅有成员时 exists）。

**选定**：Memory 允许空 `{:set, MapSet}` / `{:zset, %{}}`；Redis 在 warm 无成员时 `SET loaded_key "1"`，读时 `exists?(set_key) or exists?(loaded_key)`。为简化跨实现，Facade 增加 `ensure_collection(key, :set | :zset)`：Memory 建空集合；Redis 用 `SET key:loaded 1`。

更简实现：**读路径**对 Redis/Memory 统一：
- Block：`sismember`；若 `!exists?(key)` 则 `list_blocked` from PG + `sadd` each + 若空则 `set(loaded)` …
Actually simplest: always use member-level for device ban; for block use SET and on empty warm do `Cache.set(loaded_key,"1")`.

## Mute / Block / DeviceBan 接线

- `Group.mute_member` → MuteCache.put/delete
- `Message.validate_not_muted` → MuteCache.muted?
- `DeviceBan.ban` → DeviceBanCache.put；解封若有则 delete
- `Session` / `TokenVerifier` → DeviceBanCache.banned? 优先，未命中回源 PG

## Outbound

`deliver_messages` 将 ChatMessage 映射为 `%{priority, inbox_seq, message}` 排序后再 chunk encode。

## Oban Workers

| Worker | Queue | 说明 |
|--------|-------|------|
| `IM.Workers.GroupInboxFanout` | `inbox_fanout` | args: body_attrs + recipient_user_ids |
| `IM.Workers.MessageBurn` | `message_burn` | schedule_in ttl_sec |
| `IM.Workers.TtlPurge` | `ttl_purge` | Cron 或 GenServer tick enqueue |

`Jobs.*` 模块保留为 facade，内部 `Oban.insert`。
