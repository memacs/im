# 离线设备系统推送 - Elixir 实现（v1）

| 项 | 内容 |
|------|------|
| 语言 | Elixir |
| 设计文档 | [mobile-push.md](../../design/mobile-push.md) |
| Kafka | [kafka-event-bus.md](kafka-event-bus.md) §2.11 |
| Roadmap | Phase 5（P5-09）、Phase 9（P9-03c） |
| 差距审查 | [gap-review-wave3.md](gap-review-wave3.md) G-50/G-51 |

---

## 1. v1 模块划分（实际代码）

| 模块 | 职责 |
|------|------|
| `IM.Delivery.Router` | 在线 → WS（`UserTracker` / Registry）；**无在线设备**时 `MobilePush.maybe_enqueue/4` |
| `IM.Cluster.GroupPusher` | 大群扇出；对用户级离线集合同样 `MobilePush` |
| `IM.Delivery.MobilePush` | 查 `push_token`、进程内队列、`EventBus.Push.publish_batch/3` |
| `IM.EventBus.Push` | 旁路 topic `:push` → Kafka `im.push`（需 `EVENT_BUS_ENABLED=true`） |
| `IM.Stores.UserDeviceStore` | `push_token` / `platform`；`PUT /api/v1/devices/:id/push-token` |

**不在 IM 仓库内**：FCM/APNs HTTP、推送服务消费者。

---

## 2. 扇出路径

### 单聊 / 预编码复用

`IM.WebSocket.Commands.MsgSend.push_to_recipients/3` 对私聊调用：

```elixir
DeliveryRouter.push_binary(app_key, uid, bin,
  exclude_device_id: excl,
  msg_id: message.msg_id,
  conv_id: message.conv_id
)
```

`Router.push_binary/4` 在 `deliver_bin/5` 返回 `recipients == 0` 时：

```elixir
MobilePush.maybe_enqueue(app_key, user_id, bin,
  online?: false,
  msg_id: opts[:msg_id],
  conv_id: opts[:conv_id]
)
```

### 群聊

`GroupPusher.push/4` 在树状/直推完成后，对 **不在 online_set** 的用户调用 `MobilePush`（同样传递 `msg_id` / `conv_id`）。

### 聊天室

**不做**离线移动推送（设计约束；`CHAT_ROOM` 走 PubSub only）。

---

## 3. MobilePush 行为

```elixir
# lib/im/delivery/mobile_push.ex（摘要）
unless online? do
  devices = UserDeviceStore.list_with_push_token(app_key, user_id)
  # GenServer 内存队列 + EventPush.publish_batch(msg_id, targets, ...)
end
```

- `online?: true` 时跳过（群路径由 `GroupPusher` 用户级判断调用）。
- `msg_id` 默认 `"unknown"` 若未传；单聊/群路径现已传入真实 `msg_id`。
- **禁止**在 `CMD_MSG_SEND` 同步路径 `await` Kafka produce（`EventBus.publish` 非阻塞或 no-op）。

---

## 4. Event Bus 与 Kafka

默认配置（`config.exs` / K8s ConfigMap）：

- `event_bus_enabled: false` — 旁路关闭，`im.push` 不出节点。
- 生产需 Kafka 旁路时：`EVENT_BUS_ENABLED=true`、`KAFKA_BROKERS=...`、`EVENT_BUS_PRODUCER=brod`。

见 [deploy-guide.md](deploy-guide.md) §Event Bus。

---

## 5. v1 deferred（相对设计文档）

| 设计能力 | v1 状态 |
|----------|---------|
| `IM.Delivery.PushDisplay`（title/body） | 未实现；Kafka 载荷无 display |
| Redis `push:batch:{app_key}:{msg_id}` 幂等 | 未实现 |
| `targets[].idempotency_key` | 未实现 |
| `flush_batch` 多 chunk 元数据 | `EventBus.Push` 按 500 分 chunk，无 batch_index |
| FCM/APNs | 外置服务 |

---

## 6. 验收要点

| 场景 | 期望 |
|------|------|
| 单聊，对端在线 | WS `CMD_MSG_PUSH`；`MobilePush.drain()` 为空 |
| 单聊，对端离线 + token | `RouterTest` / `MobilePushTest`：队列 1 条 |
| 群聊，成员离线 + token | `GroupPusher` 路径入队 |
| 无 `push_token` | 不入队 |
| `EVENT_BUS_ENABLED=false` | 入队 GenServer 仍执行；Kafka 无产出 |
| 聊天室 | 无 MobilePush |

---

## 7. 测试

- `test/im/delivery/mobile_push_test.exs`
- `test/im/delivery/router_test.exs` — 单聊离线 `push_binary`
