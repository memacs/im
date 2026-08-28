# 聊天室管理 - Elixir 实现

| 项 | 内容 |
|------|------|
| 语言 | Elixir |
| 设计文档 | [room.md](../../design/room.md) |
| Roadmap | Phase 6、Phase 8（P8-03 ~ P8-04） |

> **文档分级**：边缘模块 impl。行为规范见设计文档；本文仅列模块与测试要点。

---

## 1. 房间广播优化

使用 Phoenix PubSub 进行高效广播：

```elixir
defmodule IM.Room.Broadcast do
  alias Phoenix.PubSub
  
  @pubsub IM.PubSub
  
  @doc """
  广播消息给房间内所有在线成员。
  
  使用 PubSub.broadcast 一次调用，避免 per-member 单播。
  """
  def broadcast_to_room(room_id, message) do
    PubSub.broadcast(@pubsub, room_topic(room_id), {:room_message, message})
  end
  
  defp room_topic(room_id), do: "room:#{room_id}"
end
```

---

## 2. 成员计数

使用 Redis 维护房间成员计数：

```elixir
defmodule IM.Room.MemberCount do
  alias IM.Infra.Redis
  
  @doc """
  获取房间成员数。
  """
  def get_member_count(room_id) do
    case Redis.get("room:#{room_id}:member_count") do
      {:ok, nil} -> 0
      {:ok, count} -> String.to_integer(count)
    end
  end
  
  @doc """
  增加成员计数。
  """
  def incr_member_count(room_id) do
    Redis.incr("room:#{room_id}:member_count")
  end
  
  @doc """
  减少成员计数。
  """
  def decr_member_count(room_id) do
    Redis.incrby("room:#{room_id}:member_count", -1)
  end
end
```

---

## 3. 大房间推送优化

对于大房间（成员 > 500），使用树状扇出：

```elixir
defmodule IM.Room.LargeRoom do
  @doc """
  大房间推送优化。
  
  1. 按节点分组
  2. 每个节点批量推送
  """
  def push_to_large_room(room_id, message, member_count) when member_count > 500 do
    # 1. 获取房间在线成员（按节点分组）
    online_by_node = IM.Presence.Tracker.get_room_members_by_node(room_id)
    
    # 2. 每个节点批量推送
    encoded = encode_message(message)
    
    Enum.each(online_by_node, fn {node, members} ->
      push_to_node_batch(node, encoded, members)
    end)
  end
  
  defp push_to_node_batch(node, encoded, members) do
    # 通过 Erlang 消息发送到远程节点
    :erlang.send({:room_push, node}, {:batch, encoded, members})
  end
end
```

