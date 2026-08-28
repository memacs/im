# 群组管理 - Elixir 实现

| 项 | 内容 |
|------|------|
| 语言 | Elixir |
| 设计文档 | [group.md](../../design/group.md) |
| Roadmap | Phase 5（P5-*）、Phase 8（P8-01 ~ P8-02） |

> **文档分级**：边缘模块 impl。行为规范见设计文档；本文仅列模块与测试要点。

---

## 1. 模块

| 模块 | 职责 |
|------|------|
| `IM.WebSocket.Commands.Group.*` | `CMD_GROUP_*` 各子命令 |
| `IM.Services.Group` | 群 CRUD、成员、角色 |
| `IM.Stores.GroupStore` | 群与成员持久化 |
| `IM.Permission.MuteCache` | 群禁言热路径（见 [permission-cache.md](permission-cache.md)） |
| `IM.Services.GroupChat` | 群消息 recipients（见 [modular-architecture.md](modular-architecture.md)） |

---

## 2. Handler 组织

按 [project-structure.md](project-structure.md) `websocket/commands/`，每个 cmd 独立模块：

```
lib/im/websocket/commands/group/
  create.ex
  dismiss.ex
  join.ex
  leave.ex
  kick.ex
  ...
```

---

## 3. 群消息扇出

```elixir
# IM.Services.GroupChat — 服务层输出逻辑 recipients（含离线成员，用于写扩散）
def determine_recipients(%{from: from}, members) do
  recipients =
    Enum.map(members, fn
      ^from -> {:user_other, from}
      uid -> {:user, uid}
    end)

  {:ok, recipients}
end
```

在线过滤在 `IM.Delivery.Router` + `UserTracker` 完成；大群走树状扇出（`IM.Cluster.GroupPusher`）。

树状参数（扇出度 8、RPC 超时 2s、慢节点隔离等）见设计 [group.md](../../design/group.md) §5.1；写扩散见同文档 §6。

---

## 4. 成员变更推送

群解散、踢人、邀请等操作成功后，向相关成员推送 `CMD_GROUP_*_PUSH`。

---

## 5. 群聊存储与写扩散

设计见 [group.md](../../design/group.md) §6、[database-design.md](../../design/database/database-design.md) §3。

```elixir
defmodule IM.Services.GroupChat.Persist do
  @doc """
  1. INSERT message_bodies（正文 1 份）
  2. insert_all user_inbox 瘦行（每成员 msg_id + inbox_seq）
  """
  def persist!(body_attrs, member_user_ids) do
    Repo.transaction(fn ->
      {:ok, body} = MessageBodyStore.insert(body_attrs)
      inbox_rows = build_inbox_rows(body, member_user_ids)
      GroupInboxFanout.insert_all_inbox(inbox_rows)
      body
    end)
  end
end
```

### 5.1 `insert_all` 分批

```elixir
defmodule IM.Stores.GroupInboxFanout do
  @chunk_size 500

  def insert_all_inbox(rows) when is_list(rows) do
    rows
    |> Enum.chunk_every(@chunk_size)
    |> Enum.each(fn chunk ->
      Repo.insert_all(UserInbox, chunk)
    end)
  end
end
```

按 `(app_key, user_id)` 分片键将 rows 分组后 **并行** `Task.async_stream`（上限与 DB 连接池协调）。

### 5.2 ACK 与 inbox 写扩散解耦（大群可选）

```elixir
defmodule IM.Services.GroupChat do
  def send_and_ack(params, ctx) do
    with {:ok, canonical} <- MessageStore.insert_body(params),
         :ok <- InboxFanout.insert_sender_row(canonical, ctx.user_id) do
      # 同步 ACK — 不等待全员 inbox
      ack = build_server_received_ack(canonical)
      _ = GroupInboxFanoutJob.enqueue(canonical, ctx)

      {:ok, %{ack: ack, msg_id: canonical.msg_id}}
    end
  end
end
```

`IM.Jobs.GroupInboxFanout`（Oban）：幂等 `insert_all` 其余成员；失败重试；Telemetry `im_group_inbox_fanout_lag_ms`。

离线 `OFFLINE_PULL`：若 `user_inbox` 缺行，fallback `MessageStore.list_by_conv_seq(conv_id, after: cursor)`。

### 5.3 读扩散（`read_fanout`，大群）

设计决策与 Feature Flag 见 [group.md](../../design/group.md) §6.3、§6.3.1。

```elixir
defmodule IM.Group.FanoutPolicy do
  @moduledoc """
  写扩散 / 读扩散统一判定。发消息、离线拉取、Oban Job 均调用本模块，禁止散落 threshold 判断。
  """

  @type storage_mode :: :write_fanout | :read_fanout

  @doc """
  返回群当前应使用的存储模式（只读，不晋升）。
  """
  @spec storage_mode(map(), map()) :: storage_mode()
  def storage_mode(group, app_config) do
    cond do
      global_read_fanout_disabled?() ->
        :write_fanout

      group.storage_mode_override in [:write_fanout, :read_fanout] ->
        group.storage_mode_override

      group.storage_mode == :read_fanout ->
        :read_fanout

      not app_config.group_read_fanout_enabled ->
        :write_fanout

      group.member_count > app_config.group_read_fanout_threshold ->
        :read_fanout

      true ->
        :write_fanout
    end
  end

  @doc """
  成员变更后调用：若应读扩散且当前为 write_fanout，则晋升并持久化。
  降员不自动回退。
  """
  @spec maybe_promote!(map(), map()) :: {:ok, map()} | {:noop, map()}
  def maybe_promote!(group, app_config) do
    if storage_mode(group, app_config) == :read_fanout and group.storage_mode != :read_fanout do
      GroupStore.promote_read_fanout!(group)
    else
      {:noop, group}
    end
  end

  defp global_read_fanout_disabled? do
    System.get_env("IM_GROUP_READ_FANOUT_ENABLED") == "false"
  end
end
```

```elixir
defmodule IM.Services.GroupChat do
  def persist_group_message(params, ctx) do
    group = GroupStore.get!(ctx.app_key, params.group_id)
    app_config = AppConfigStore.get!(ctx.app_key)

    case FanoutPolicy.storage_mode(group, app_config) do
      :read_fanout ->
        MessageStore.insert_body_only(params)

      :write_fanout ->
        MessageStore.insert_with_inbox_fanout(params)
    end
  end
end
```

- 扩员 / 建群成功后：`FanoutPolicy.maybe_promote!/2`（**非**发消息热路径）
- 离线：`OfflinePull.list_by_conv_seq(conv_id, after: cursor)`（无 `user_inbox` JOIN）
- **不** enqueue `GroupInboxFanout` Job（`read_fanout` 群）

### 5.4 配置项（Feature Flag）

| 键 | 层级 | 默认 | 说明 |
|----|------|------|------|
| `IM_GROUP_READ_FANOUT_ENABLED` | 全局 env | 未设 | `false` 时全站强制写扩散（紧急回滚） |
| `group_read_fanout_enabled` | 租户 `app_configs` | `true` | 按 `app_key` 灰度开关 |
| `group_read_fanout_threshold` | 租户 `app_configs` | `500` | 大于此人数量且 Flag 开启时晋升 `read_fanout` |
| `group_inbox_fanout_async` | 租户 | `false` | 小群：ACK 不等待全员 `user_inbox` 写完 |
| `group_inbox_insert_chunk_size` | 租户 | `500` | `insert_all` 每批行数（仅 `write_fanout`） |

`groups.storage_mode` / `groups.storage_mode_override` 见 [database-design.md](../../design/database/database-design.md) §3.1。

---

## 6. 验收要点

- `CMD_GROUP_CREATE` 创建群并返回 `group_id`
- 小群消息：`message_bodies` 1 行 + 全员 `user_inbox` 瘦行
- 大群（read_fanout）：`message_bodies` 1 行；`OFFLINE_PULL` 带 `conv_id` 按 `conv_seq` 拉取
- 非成员发群消息返回 `CODE_MSG_NO_PERMISSION` 或 `CODE_GROUP_NOT_MEMBER`
- 5000 人群：`read_fanout` 写库 1 INSERT/msg；小群 `insert_all` 分批写扩散（P5-10/12）
