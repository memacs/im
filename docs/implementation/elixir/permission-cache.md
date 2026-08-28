# 权限热缓存 - Elixir 实现

| 项 | 内容 |
|------|------|
| 语言 | Elixir |
| 设计文档 | [permission-cache.md](../../design/permission-cache.md) |
| Roadmap | P8-08（拉黑）；P8-10（群禁言）；P2-13（设备封禁） |

> **文档分级**：横切 impl。行为规范见设计文档；本文列模块落位与测试要点。

---

## 1. 模块落位

| 模块 | 职责 |
|------|------|
| `IM.Permission.L1` | 进程内 ETS，短 TTL（`permission_l1_ttl_ms`，默认 10s） |
| `IM.Permission.Invalidator` | 订阅 `im:permission:invalidate`，清本节点 L1 |
| `IM.Permission.BlockCache` | 拉黑：L1 → L2 SET `im:block:{app}:{blocker}` |
| `IM.Permission.MuteCache` | 禁言：L1 → L2 ZSET `im:mute:{app}:{group}`（score=`muted_until` ms） |
| `IM.Permission.DeviceBanCache` | 封禁：L1 → L2 STRING `im:device_ban:{app}:{user}:{device}` |
| `IM.Permission.Reconciler` | 抽样比对 PG↔L2，修复漂移（Oban `IM.Workers.PermissionReconcile`） |
| `IM.Permission.Telemetry` | `im.permission.check` / `im.permission.cache_drift` |
| `IM.Cache` | SET/ZSET/STRING Behaviour（Memory / Redis） |

调用方：

- `IM.Services.Friend.check_send_permission/2` → `BlockCache`
- `IM.Services.Message` 群发前 → `MuteCache.muted?/3`
- `IM.Services.Session` / `IM.Auth.TokenVerifier` → `DeviceBanCache`
- `IM.Services.DeviceBan.ban/5` → `DeviceBanCache.put/3` + KICK

读路径：**L1 → L2 → PG**；命中 L2/PG 后回填 L1。  
写路径：**PG 成功 → 更新 L2 → `Invalidator.broadcast` → 回填本节点 L1**。

---

## 2. API 摘要

```elixir
BlockCache.blocked?(app_key, blocker, blocked) :: boolean()
BlockCache.put(app_key, blocker, blocked) :: :ok
BlockCache.delete(app_key, blocker, blocked) :: :ok

MuteCache.muted?(app_key, group_id, user_id) :: boolean()
MuteCache.put(app_key, group_id, user_id, muted_until_ms) :: :ok  # 0 = 解禁

DeviceBanCache.banned?(app_key, user_id, device_id) :: boolean()
DeviceBanCache.ensure_allowed(app_key, user_id, device_id) :: :ok | {:error, Error.t()}
DeviceBanCache.put / delete

Invalidator.broadcast({:block, app, blocker} | {:mute, app, group} | {:device_ban, app, user, device})

Reconciler.run(app_key, sample: 200) :: %{block: n, mute: n, device_ban: n}
Jobs.PermissionReconcile.enqueue(app_key)  # Oban；PERMISSION_RECONCILE_AUTO 开 Cron
```

---

## 3. 写路径（拉黑）

```elixir
with {:ok, _} <- FriendStore.upsert_friendship(... status: "blocked"),
     :ok <- BlockCache.put(ctx.app_key, ctx.user_id, peer) do
  # PUSH ...
end
```

`BlockCache.put` 内：`SADD` + loaded 标记 → `Invalidator.broadcast({:block, ...})` → `L1.put(true)`。

空拉黑名单用 companion key `im:block:{app}:{blocker}:loaded`，避免反复打 PG。

---

## 4. 测试要点

| 场景 | 断言 |
|------|------|
| L1 命中 | 不访问 L2/PG（测 Telemetry `layer=l1`） |
| L2 有 SET | `blocked?` true；冷 key 回源后批量 `SADD` |
| 拉黑后 | 立即 true；broadcast 后他节点 L1 miss |
| 取消拉黑 | `SREM` 后 false |
| 群禁言过期 | `muted_until < now` 允许发送；ZSET 惰性 `ZREM` |
| 设备封禁 | sessions / TokenVerifier → `device_banned` |
| Reconciler | 清空 L2 后 `run_once` 修复且 `block >= 1` |

测试用 `IM.Cache.Memory` + `L1.reset!()`，不依赖真实 Redis。

---

## 5. 配置

```elixir
config :im,
  permission_l1_ttl_ms: 10_000,
  permission_reconcile_auto: false

# runtime：PERMISSION_RECONCILE_AUTO=true → Cron 默认 "0 */6 * * *"
```
