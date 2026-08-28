# 数据库层 - Elixir 实现

| 项 | 内容 |
|------|------|
| 语言 | Elixir |
| 设计文档 | [database-design.md](../../design/database/database-design.md) |
| Roadmap | Phase 3（P3-04）、Phase 4（P4-05）、Phase 9（P9-02） |

---

## 1. 技术栈

| 组件 | 选型 |
|------|------|
| RDBMS | PostgreSQL + Ecto |
| 缓存 | Redis（Redix，经 `IM.Cache` 封装） |
| 迁移 | `priv/repo/migrations/` |

---

## 2. 审计时间字段

与 [database-design.md §通用约定](../../design/database/database-design.md#审计时间字段created_at--updated_at) 对齐：库表列名为 **`created_at` / `updated_at`**（非 Ecto 默认的 `inserted_at`）。

### 2.1 Schema

```elixir
defmodule IM.Schemas.User do
  use Ecto.Schema
  import Ecto.Changeset

  @timestamps_opts [type: :utc_datetime_usec, inserted_at: :created_at, updated_at: :updated_at]

  schema "users" do
    field :user_id, :string

    timestamps()
  end
end
```

Migration：

```elixir
create table(:users) do
  add :user_id, :string, null: false
  timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime_usec)
end
```

### 2.2 写入路径

| 方式 | 要求 |
|------|------|
| `Repo.insert` / `Repo.update` + **changeset** | 依赖 `timestamps()` 自动维护（**推荐**） |
| `Repo.insert_all` / `Repo.update_all` | **手动**设置 `created_at` / `updated_at` |
| 原生 SQL | `INSERT` 两列均写；`UPDATE` 必须 `SET updated_at = NOW()` |
| `on_conflict` upsert | `on_conflict: {:replace, [:field, ..., :updated_at]}`，**不得**替换 `created_at` |

```elixir
# update_all 示例
now = DateTime.utc_now()

from(m in Message, where: m.msg_id == ^msg_id)
|> Repo.update_all(set: [recalled: true, updated_at: now])
```

### 2.3 禁止事项

- 业务 `cast` 中**不要**暴露 `created_at` / `updated_at` 给客户端入参
- 禁止 `UPDATE ... SET created_at = ...`（数据修复除外）
- 禁止绕过 changeset 的 `Repo.update_all` 且遗漏 `updated_at`

### 2.4 可选辅助

```elixir
defmodule IM.Repo do
  def utc_now, do: DateTime.utc_now(:microsecond)

  def set_updated_at(attrs) when is_map(attrs) do
    Map.put(attrs, :updated_at, utc_now())
  end
end
```

---

## 3. Schema 映射

| 设计表 | Ecto Schema | 模块 |
|--------|-------------|------|
| `message_bodies` | `IM.Schemas.MessageBody` | 单聊/群聊正文（每 `msg_id` 一行） |
| `user_inbox` | `IM.Schemas.UserInbox` | 收件箱瘦行（写扩散） |
| `conversations` | `IM.Schemas.Conversation` | 会话列表、`last_read_conv_seq`、未读 |
| `groups` / `group_members` | `IM.Schemas.Group*` | 群管理 |
| `users` / `user_devices` | `IM.Schemas.User*` | 用户与设备 |
| `friendships` / `friend_requests` | `IM.Schemas.Friendship*` | 好友与请求 |
| `msg_sequences` | `IM.Schemas.MsgSequence` | `conv_seq`/`inbox_seq` PG 兜底；`msg_id_fallback` 兜底发号 |
| `id_workers` | `IM.Schemas.IdWorker` | Snowflake worker 租约镜像 |

---

## 4. Store 抽象

业务层只调用 Behaviour，不直接 `Repo`：

```elixir
defmodule IM.Stores.MessageStore do
  @callback insert_idempotent(map(), IM.Domain.MessageContext.t()) ::
              {:ok, struct()} | {:error, term()}
  @callback list_inbox_joined(String.t(), String.t(), keyword()) :: [struct()]
  @callback list_conv_joined(String.t(), String.t(), String.t(), keyword()) :: [struct()]

  def insert_idempotent(msg, ctx), do: impl().insert_idempotent(msg, ctx)
  def list_inbox_joined(app, user, opts), do: impl().list_inbox_joined(app, user, opts)
  defp impl, do: Application.get_env(:im, :message_store, IM.Stores.MessageStore.Pg)
end
```

测试环境配置 `IM.Stores.MessageStore.Memory`。

---

## 5. 分片策略

Phase 3–4 单库单表 + 索引；规模扩展时：

1. `user_inbox` 按 `hash(app_key, user_id) % N` 路由；`message_bodies` 可按 `msg_id` 或独立库
2. 时间分区：`PARTITION BY RANGE (created_at)` 月度分区
3. `inbox_seq` 由 Redis `INCR` 或 DB 序列生成，见 `IM.Services.Sequence`

---

## 6. Redis 用途

与 [database-design.md §二](../../design/database/database-design.md#二redis-缓存设计) 对齐（节选）：

| 键模式 | 用途 |
|--------|------|
| `im:{app_key}:seq:inbox:{user_id}` | inbox_seq 发号 |
| `im:{app_key}:seq:conv:{conv_id}` | conv_seq 发号 |
| `im:id:worker:{worker_id}` | Snowflake worker 租约（DD-039） |
| `im:dedup:cid:{conn_id}:{cid}` | 网关同连接 cid 去重 |
| `im:dedup:msg:{app_key}:{from_uid}:{client_msg_id}` | 消息幂等 |
| `im:token:{token_hash}` | access token 校验缓存 |
| `im:unread:{app_key}:{user_id}` | 未读数 Hash（热路径） |
| `im:block:` / `im:mute:` / `im:device_ban:` | 权限热缓存（见 permission-cache.md） |

**在线定位**：`Phoenix.Tracker`，非 Redis。离线消息：`user_inbox`（PG），无 Redis 离线队列。

---

## 7. 验收要点

- Migration 与 `database-design.md` 表结构一致
- 可变更表均含 `created_at` + `updated_at`；UPDATE 路径刷新 `updated_at`
- 消息幂等唯一约束 `(app_key, from_uid, client_msg_id)`（partial unique，`client_msg_id IS NOT NULL`）
- `conv_seq` / `inbox_seq` 唯一约束防止发号重复
- 离线拉取查询走 `(app_key, user_id, inbox_seq)` 索引

---

## 8. `msg_id` 发号（DD-039）

| 模块 | 职责 |
|------|------|
| `IM.Services.MsgId` | `next/1` → 十进制字符串；正常 Snowflake，失败 PG 兜底 |
| `IM.Services.MsgId.WorkerLease` | Redis `SET NX` 租约 + 续期 |
| `IM.Workers.MsgIdReconcile` | Oban：兜底计数器与 `message_bodies` 对账 |

位布局、对账、迁移见 [msg-id-snowflake.md](../../design/msg-id-snowflake.md)。`conv_seq` / `inbox_seq` 仍由 `IM.Services.Sequence`（Redis `INCR`）。
