# 应用通道 - Elixir 实现

| 项 | 内容 |
|------|------|
| 语言 | Elixir |
| 设计文档 | [app-channel.md](../../design/app-channel.md) |
| Roadmap | Phase 11（P11-01 ~ P11-05） |
| 依赖 | Phase 2（鉴权）、Phase 6（PubSub）、Phase 9（Kafka EventBus） |

---

## 1. 模块划分

| 模块 | 职责 |
|------|------|
| `IM.WebSocket.Commands.ChannelSubscribe` | `CMD_CHANNEL_SUBSCRIBE_*` |
| `IM.WebSocket.Commands.ChannelPublish` | `CMD_CHANNEL_PUBLISH` / `ACK` |
| `IM.Services.Channel` | 订阅/ACL、上行受理、internal publish 入口 |
| `IM.Delivery.ChannelRouter` | PubSub `broadcast` + 预编码 `CMD_CHANNEL_PUSH` |
| `IM.EventBus.AppEvents` | 异步写 `im.app_events` |
| `IM.Channel.RateLimiter` | 连接 1/s + Channel 聚合 5000/s |
| `IMWeb.Internal.V1.ChannelController` | `POST .../channels/:id/publish` |
| `IMWeb.Api.V1.ChannelController` | 客户端 REST 对等 |

---

## 2. 订阅（PubSub）

```elixir
defmodule IM.Services.Channel do
  @pubsub IM.PubSub
  @topic_prefix "channel:"

  @spec subscribe(String.t(), String.t(), pid()) :: :ok | {:error, term()}
  def subscribe(app_key, channel_id, socket_pid) do
    topic = topic(app_key, channel_id)
    Phoenix.PubSub.subscribe(@pubsub, topic)
    # 记录 socket_pid ↔ channels（断线清理）
    :ok
  end

  defp topic(app_key, channel_id), do: "#{@topic_prefix}#{app_key}:#{channel_id}"
end
```

Socket 进程 `handle_info` 收到 `{:channel_push, packet_binary}` → `OutboundQueue.enqueue`（LOW 带，可丢）。

---

## 3. 后端广播

```elixir
def publish_down(app_key, channel_id, %{content_type: ct, payload: payload}, ctx) do
  with :ok <- ACL.allow_internal_publish?(app_key, channel_id, ctx),
       {:ok, packet_binary} <- encode_push(channel_id, ct, payload, ctx) do
    Phoenix.PubSub.broadcast(IM.PubSub, topic(app_key, channel_id), {:channel_push, packet_binary})
    IM.EventBus.AppEvents.publish_down(app_key, channel_id, ctx, ct, payload)
    :ok
  end
end
```

**不实现树状扇出**：`ChannelRouter` **仅** `PubSub.broadcast`，**不**调用 `IM.Cluster.GroupPusher` / `FanoutBatcher`（见设计文档 §7.4）。发布与订阅同 topic，无 Tracker 查成员步骤。

---

## 3.1 扇出路径（对比大群）

```
internal publish
  → encode_push/1（全集群 1 次）
  → Phoenix.PubSub.broadcast(topic, {:channel_push, packet_binary})
  → 各节点：订阅了 topic 的 socket 进程 handle_info
  → OutboundQueue.enqueue(..., priority: :low)   # 可丢
```

| 检查项 | 期望 |
|--------|------|
| 无 GroupPusher | `ChannelRouter` 不依赖 Phase 5 树状扇出 |
| 无成员查询 | publish 路径不查 DB/Redis 成员列表 |
| 编码一次 | 全节点共享同一份 `packet_binary` |
| 多节点 | 与 Phase 6 聊天室相同 PubSub 基础设施 |

压测不达标时：先扩节点分散订阅，再考虑节点内投递 yield；**不**引入业务层树。

---

## 4. 客户端上行 + 限速

```elixir
def publish_up(%ChannelPublish{} = req, ctx) do
  with :ok <- ACL.allow_client_publish?(ctx.app_key, req.channel_id, ctx.user_id),
       :ok <- RateLimiter.allow_conn?(ctx.user_id, ctx.device_id),
       :ok <- RateLimiter.allow_channel_aggregate?(ctx.app_key, req.channel_id) do
    event_id = IM.Id.generate()
    IM.EventBus.AppEvents.publish_up(req, ctx, event_id)
    {:ok, %ChannelPublishAck{channel_id: req.channel_id, event_id: event_id, accepted: true}}
  else
    :rate_limited -> :drop_silent
    err -> err
  end
end
```

`RateLimiter`：`:persistent_term` 或 Redis 滑动窗口；默认连接 **1/s burst 2**。

---

## 5. Kafka

```elixir
defmodule IM.EventBus.AppEvents do
  @topic "im.app_events"

  def publish_up(%ChannelPublish{} = req, ctx, event_id) do
  GenServer.cast(IM.EventBus, {:app_event, %AppEvent{
    event_id: event_id,
    direction: :APP_EVENT_UP,
    app_key: ctx.app_key,
    trace_id: ctx.trace_id,
    channel_id: req.channel_id,
    user_id: ctx.user_id,
    device_id: ctx.device_id,
    content_type: req.content_type,
    payload: req.payload,
    client_event_id: req.client_event_id
  }})
  end
end
```

分区键：`"#{app_key}:#{channel_id}"`。

---

## 6. 验收要点（Phase 11）

| 场景 | 期望 |
|------|------|
| 订阅 + internal publish | 10 连接收 `CMD_CHANNEL_PUSH` |
| 客户端 publish | `ACK` + Kafka 有 `APP_EVENT_UP` |
| 超 1/s | 第 3 条起静默丢弃 |
| 离线客户端 | 不收下行；无补发 |
| 与聊天隔离 | 无 `ChatMessage`、无 `OFFLINE_PULL` |
| 10 万订阅压测 | 有报告；P99 延迟可接受；**走 PubSub broadcast，非树状扇出** |

---

## 7. 相关文档

- [kafka-event-bus.md](../../design/kafka-event-bus.md) §2.12
- [dual-channel-api.md](../../design/dual-channel-api.md) §4.4 internal 路由
- [room.md](../../design/room.md) PubSub 参考（设计侧 broadcast；**勿**照搬实现草图树状扇出）
- [app-channel.md](../../design/app-channel.md) §7.4 扇出模型
