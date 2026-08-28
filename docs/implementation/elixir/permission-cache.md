# 权限热缓存 - Elixir 实现

| 项 | 内容 |
|------|------|
| 语言 | Elixir |
| 设计文档 | [permission-cache.md](../../design/permission-cache.md) |
| Roadmap | P8-08（拉黑）；群禁言随 Phase 5 群消息；设备封禁 P2-13 |

> **文档分级**：横切 impl。行为规范见设计文档；本文列模块落位与测试要点。

---

## 1. 模块落位

| 模块 | 职责 |
|------|------|
| `IM.Permission.BlockCache` | 拉黑 `SISMEMBER` / 回填 / 失效 |
| `IM.Permission.MuteCache` | 群禁言 `ZSCORE` + 过期清理 |
| `IM.Permission.DeviceBanCache` | 设备封禁标记 |
| `IM.Permission.Invalidator` | 订阅 PubSub，清节点 ETS |
| `IM.Cache.Redis` | 底层 Redis（见 dependency-abstraction） |

调用方：

- `IM.Services.Friend.check_send_permission/2` → `BlockCache`
- `IM.Services.GroupChat` 发消息前 → `MuteCache`
- `IM.Services.Auth` / `IM.Services.DeviceBan` → `DeviceBanCache`

---

## 2. Behaviour 示意

```elixir
defmodule IM.Permission.BlockCache do
  @moduledoc """
  好友拉黑热缓存。PostgreSQL 为权威源，Redis SET 为热路径。

  设计：[`permission-cache.md`](../../../docs/design/permission-cache.md) §3.1
  """

  @doc """
  判断接收方是否拉黑了发送方。

  ## 示例

      BlockCache.blocked?("demo", "alice", "bob")
      #=> true   # alice 拉黑了 bob，bob 不能给 alice 发消息

  ## 返回值

  - `true` / `false`
  """
  @spec blocked?(String.t(), String.t(), String.t()) :: boolean()
  def blocked?(app_key, blocker_user_id, blocked_user_id), do: ...
end
```

---

## 3. 写路径（拉黑示例）

```elixir
# IM.Services.Friend.BlockHandler（示意）
with {:ok, _} <- FriendshipStore.block(context, user_id),
     :ok <- BlockCache.add(context.app_key, context.user_id, user_id),
     :ok <- Invalidator.broadcast({:block, context.app_key, context.user_id}) do
  # PUSH ...
end
```

顺序：**PG 成功后再更新 Redis**；Redis 失败记指标并依赖下次读回源（或 Oban 修复）。

---

## 4. 测试要点

Redis 键与 [database-design.md](../../design/database/database-design.md) §二.9 / [permission-cache.md](../../design/permission-cache.md) §3 一致：`im:block:`、`im:mute:`、`im:device_ban:`。

| 场景 | 断言 |
|------|------|
| Redis 有 key | `blocked?` 不访问 Repo |
| Redis 无 key | 回源 PG 并回填 |
| 拉黑后 | `blocked?` 立即为 true；其他节点 L1 失效后一致 |
| 取消拉黑 | `SREM` 后 `blocked?` 为 false |
| 群禁言过期 | `muted_until < now` 时允许发消息 |
| 设备封禁 | 登录 / AUTH 返回 403 / 1001 |

测试用 `IM.Cache.Memory` 或 Mox，不依赖真实 Redis。

---

## 5. 配置

```elixir
# config/runtime.exs（示意）
config :im, :block_cache, IM.Permission.BlockCache
config :im, :permission_l1_ttl_ms, 10_000
```
