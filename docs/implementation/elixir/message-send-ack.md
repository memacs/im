# 发消息与 ACK - Elixir 实现

| 项 | 内容 |
|------|------|
| 语言 | Elixir |
| 设计文档 | [message-send-ack.md](../../design/message-send-ack.md) |
| Roadmap | Phase 3（P3-01 ~ P3-09） |

---

## 1. 主路径（同步）

```elixir
defmodule IM.Services.Message.Send do
  def handle(%Packet{} = packet, socket) do
  with :ok <- IM.Gateway.Dedup.check_cid(packet, socket),
       {:ok, req} <- decode(packet),
       :ok <- IM.Domain.Message.validate_send(req, socket.assigns),
       {:ok, msg} <- IM.Stores.MessageStore.insert_idempotent(req, socket.assigns),
       :ok <- push_delivery(msg, socket.assigns) do
    ack = IM.Protocol.Reply.ack_down(packet, :SERVER_RECEIVED, msg)
    {:reply, ack, socket}
  end
  end
end
```

**禁止** async 等待 Hook/Kafka 后再回 `SERVER_RECEIVED`。

---

## 2. 模块划分

| 模块 | 职责 |
|------|------|
| `IM.WebSocket.Commands.MsgSend` | `CMD_MSG_SEND` 入口 |
| `IM.Services.SingleChat` / `GroupChat` / `RoomChat` | 计算 recipients |
| `IM.Delivery.Router` | 定位设备、编码 PUSH、**离线写 `im.push`** |
| `IM.WebSocket.Commands.MsgAck` | `ACK_UP` / `ACK_DOWN` |
| `IM.Gateway.Dedup` | `Packet.cid` 短窗口去重 |

`CMD_MSG_SEND` 含 `burn_after_read=true` 时，`validate_send` 内调用 `Burn.validate!/2`（租户开关、仅单聊、`burn_ttl_sec` 上限；见 [burn-after-read.md](burn-after-read.md)）。

---

## 3. 双阶段 ACK

| 阶段 | 触发 | `seq` |
|------|------|-------|
| `SERVER_RECEIVED` | SEND 成功同步返回 | 回传 SEND 的 `seq` |
| `CLIENT_RECEIVED` | 对端 `ACK_UP` 后推送 | `0` |

群聊 `CLIENT_RECEIVED`：首个在线成员 `ACK_UP` 即通知发送方。

---

## 4. 推送规则

- 发送设备 **不收** 自己消息的 `CMD_MSG_PUSH`
- 发送方其他设备通过 `{:user_other, from_uid}` recipient 推送
- 批量下行用 `CMD_MSG_PUSH_BATCH`，上限取自 `AuthResp.push_batch_max`
- 设备**离线**且有 `push_token` → 异步写 `im.push`（见 [mobile-push.md](mobile-push.md)）

---

## 5. 验收要点

- 单聊 SEND → 同步 `ACK_DOWN(SERVER_RECEIVED)` → 对端 PUSH
- `(app_key, from, client_msg_id)` 幂等：重复 SEND 不重复 PUSH
- SEND 失败回 `CMD_ERROR`，连接保持
- 群扇出：`Packet.encode` **仅 1 次**（见 [zero-copy-delivery.md](zero-copy-delivery.md)）

---

## 6. 出站优先级队列 `IM.Delivery.OutboundQueue`

设计见 [message-send-ack.md](../../design/message-send-ack.md) §7。

**落位**：纯状态机挂在 `IMWeb.PacketTransport` 的 `state.outbound`（非独立 GenServer）。下行统一 `{:im_push, bin, meta}`（`meta` 含 `priority` / `inbox_seq`）。

| 能力 | 行为 |
| --- | --- |
| WFQ | 三带权重默认 8/4/1；deficit 选带 |
| 老化 | LOW→NORMAL / NORMAL→HIGH / LOW→HIGH（阈值见 config） |
| burst | 同带连续写出 ≤ `priority_max_burst`（默认 16）后强制换带 |
| coalesce | 深度 > `outbound_coalesce_depth`（默认 32）时同带连续 `CMD_MSG_PUSH` 合并为 `CMD_MSG_PUSH_BATCH` |
| 溢出 | 深度 > `outbound_max_depth` 丢最旧 LOW |
| 直写 | 队列空且 HIGH 可不入队直推 |

```elixir
q = OutboundQueue.new()
q = OutboundQueue.enqueue(q, %{
  priority: :high,
  inbox_seq: 100,
  packet_binary: bin,
  enqueued_at_ms: System.system_time(:millisecond)
})
{bins, q} = OutboundQueue.drain(q, 16)
```

`IM.Delivery.Outbound.sort_by_priority/1` 用于 `FanoutBatcher.deliver_messages/3` 批内排序（与连接队列互补）。

### 测试要点（P3-09 / Delivery 阶段）

| 场景 | 期望 |
| --- | --- |
| 仅 HIGH 持续入队 | LOW 仍能获得写出份额 |
| 同带多条 | 按 `inbox_seq` 升序写出 |
| 老化 | 等待超阈值后升带优先写出 |
| coalesce | 深度超阈值时多条 PUSH → 一条 PUSH_BATCH |
| UI | 客户端按 `conv_seq` 排序，与到达序无关 |

