# 离线设备系统推送 - Elixir 实现

| 项 | 内容 |
|------|------|
| 语言 | Elixir |
| 设计文档 | [mobile-push.md](../../design/mobile-push.md) |
| Kafka | [kafka-event-bus.md](kafka-event-bus.md) §2.11 |
| Roadmap | Phase 5（P5-09）、Phase 9（P9-03c） |

---

## 1. 模块划分

| 模块 | 职责 |
|------|------|
| `IM.Delivery.Router` | 扇出：在线 → WS；离线设备收集进 `MobilePush` |
| `IM.Delivery.MobilePush` | 判定 eligibility、聚合 `targets`、构造 `PushNotificationBatchEvent` |
| `IM.Delivery.PushDisplay` | 从 `ChatMessage` 生成 `title` / `body` |
| `IM.EventBus.Push` | 编码并 `publish(:push, batch_event)`；超限时 `chunk_targets/2` |
| `IM.Stores.DeviceStore` | 查 `user_devices`（`push_token`、`platform`） |

推送服务（消费 `im.push`、调 APNs/FCM）**不在** IM 仓库内。

---

## 2. Delivery 扇出

```elixir
defmodule IM.Delivery.Router do
  def deliver(recipients, encoded_packet, message, context) do
  push_targets =
    Enum.flat_map(recipients, fn recipient ->
      devices = DeviceStore.list_devices(context.app_key, recipient.user_id)

      Enum.reduce(devices, [], fn device, acc ->
        cond do
          device_online?(device) ->
            push_websocket(device, encoded_packet, message)
            acc

          MobilePush.eligible?(device, message, context) ->
            [MobilePush.build_target(device, message, context) | acc]

          true ->
            acc
        end
      end)
    end)

    MobilePush.flush_batch(message, push_targets, context)
    :ok
  end
end
```

**禁止**在 `handle_msg_send` 同步路径 `await` Kafka produce。

---

## 3. 批量事件构造

```elixir
defmodule IM.Delivery.MobilePush do
  @batch_max Application.compile_env(:im, :push_batch_targets_max, 500)

  def flush_batch(_message, [], _context), do: :ok

  def flush_batch(message, targets, context) do
    display = PushDisplay.build(message)
    chunks = Enum.chunk_every(targets, @batch_max)
    total = length(chunks)

    chunks
    |> Enum.with_index()
    |> Enum.each(fn {chunk, index} ->
      event = %{
        event_id: Ecto.UUID.generate(),
        timestamp: System.system_time(:millisecond),
        app_key: context.app_key,
        trace_id: context.trace_id,
        msg_id: message.msg_id,
        conv_id: message.conv_id,
        chat_type: message.chat_type,
        from_user_id: message.from,
        display: display,
        targets: chunk,
        batch_index: index,
        batch_total: total
      }

      IM.EventBus.publish(:push, event)
    end)
  end

  def build_target(device, message, context) do
    %{
      user_id: device.user_id,
      device_id: device.device_id,
      platform: device.platform,
      push_token: device.push_token,
      channel: channel_for(device.platform),
      idempotency_key: idempotency_key(context.app_key, device, message)
    }
  end
end
```

---

## 4. EventBus 配置

```elixir
config :im, IM.EventBus.Kafka,
  topics: %{
    upstream: "im.upstream",
    session: "im.session",
    downstream: "im.downstream",
    push: "im.push",
    dlq: "im.dlq"
  },
  push_enabled: true,
  push_room_enabled: false,
  push_display_body_max: 100,
  push_batch_targets_max: 500
```

编码：`IM.EventBus.Encoder.encode(%PushNotificationBatchEvent{}, :protobuf)`。

---

## 5. 与幂等的关系

`MSG_SEND` 幂等重试**不得**重复写 `im.push`：

- 扇出前标记「本 `msg_id` 已 enqueue push」（Redis `push:batch:{app_key}:{msg_id}`，TTL 24h）
- `targets[].idempotency_key` 供推送服务侧 per-device 去重

---

## 6. 验收要点

| 场景 | 期望 |
|------|------|
| 单聊，对端设备在线 | 仅 WS `CMD_MSG_PUSH`，**无** `im.push` |
| 单聊，对端 1 台离线 + token | **1 条** `im.push`，`targets` 长度 1 |
| 群聊 3 人，2 人各 1 离线设备 | **1 条** `im.push`，`targets` 长度 2 |
| 群 600 离线设备 | **2 条** `im.push`（500+100），`batch_total` = 2 |
| 无 `push_token` | 不进入 `targets` |
| SEND 幂等重试 | 不重复 `im.push` |
| Kafka 不可用 | SEND ACK 与在线推送正常 |

---

## 7. 测试

```elixir
test "enqueues batch push for offline devices" do
  {:ok, msg} = send_group_message(members: 3, offline: ["bob", "carol"])
  assert_push_batch(msg_id: msg.msg_id, target_count: 2)
  refute_push_batch(target_user: "alice")  # 发送方不收
end
```

Mock：`IM.EventBus.Mock` 断言 `:push` topic 载荷为 `PushNotificationBatchEvent`。
