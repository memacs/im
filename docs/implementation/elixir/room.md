# 聊天室管理 - Elixir 实现

| 项 | 内容 |
|------|------|
| 语言 | Elixir |
| 设计文档 | [room.md](../../design/room.md) |
| Roadmap | Phase 6、Phase 8（P8-03 ~ P8-04） |

> **文档分级**：边缘模块 impl。行为规范见设计文档；本文仅列模块与测试要点。

---

## 1. 在线消息广播（一律 PubSub）

聊天室在线投递 **只** 走 Phoenix PubSub，与成员数无关。不按节点做树状扇出（树状扇出仅用于**群聊**大群，见 [group.md](../../design/group.md) / `IM.Cluster.GroupPusher`）。

定稿依据：设计 [room.md](../../design/room.md) §5；与 App Channel 相同策略（见 [app-channel.md](app-channel.md)「不实现树状扇出」）。

```elixir
defmodule IM.Room.Broadcast do
  @moduledoc """
  房间消息与成员变更通知的 PubSub 广播。

  topic 约定：`room:#{app_key}:#{room_id}`（多租户隔离）。
  载荷优先传预编码 `packet_binary`，见 zero-copy-delivery.md。
  """

  alias Phoenix.PubSub

  @pubsub IM.PubSub

  @doc """
  向房间内所有已 subscribe 的连接广播。

  一次 `broadcast` 跨节点传播；各节点本地订阅者写出 WS 帧。
  排除发送设备由订阅侧或 payload 内 `exclude_device_id` 处理。
  """
  @spec broadcast_to_room(String.t(), String.t(), term()) :: :ok
  def broadcast_to_room(app_key, room_id, message) do
    PubSub.broadcast(@pubsub, room_topic(app_key, room_id), {:room_message, message})
  end

  @doc "JOIN 成功后订阅；LEAVE / 断连时 unsubscribe。"
  @spec subscribe(String.t(), String.t()) :: :ok | {:error, term()}
  def subscribe(app_key, room_id) do
    PubSub.subscribe(@pubsub, room_topic(app_key, room_id))
  end

  defp room_topic(app_key, room_id), do: "room:#{app_key}:#{room_id}"
end
```

**刻意不做**：

| 放弃 | 原因 |
|------|------|
| 成员数 > N 改树状扇出 | 与设计「优先 PubSub」冲突；两套路径难测、难运维 |
| 查 Tracker 拿全员再单播 | 聊天室目标是在线广播，PubSub 订阅即成员集合 |
| 调用 `GroupPusher` / `FanoutBatcher` | 那些模块服务群聊写扩散场景 |

大房间压力落在：PubSub 跨节点带宽、本节点慢连接背压（见 observability / outbound 队列），而不是换扇出算法。

---

## 2. 成员计数

使用 Redis 维护房间成员计数（设计 [room.md](../../design/room.md) §5）：

```elixir
defmodule IM.Room.MemberCount do
  alias IM.Infra.Redis

  @doc "获取房间成员数。"
  def get_member_count(app_key, room_id) do
    case Redis.get("room:#{app_key}:#{room_id}:member_count") do
      {:ok, nil} -> 0
      {:ok, count} -> String.to_integer(count)
    end
  end

  def incr_member_count(app_key, room_id), do: Redis.incr("room:#{app_key}:#{room_id}:member_count")

  def decr_member_count(app_key, room_id) do
    Redis.incrby("room:#{app_key}:#{room_id}:member_count", -1)
  end
end
```

DB `rooms.member_count` 异步校正，不挡 JOIN/LEAVE 热路径。

---

## 3. 验收要点

- JOIN 后本连接 subscribe 对应 topic；LEAVE / 断连 unsubscribe
- `CMD_MSG_SEND`（`CHAT_ROOM`）→ `SERVER_RECEIVED` → `PubSub.broadcast`；房间内在线成员收 `CMD_MSG_PUSH`
- 发送设备不收自身 PUSH（与 multi-device 一致）
- `target_users` 非空时：仅目标订阅者处理或服务端按列表过滤后再写本节点连接（仍不走树状扇出）
- **不存在**「成员 > 500 切换 GroupPusher」分支
