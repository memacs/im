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

设计见 [message-send-ack.md](../../design/message-send-ack.md) §7。每设备连接一个队列进程（或挂在 `UserSocket` 进程内）。

```elixir
defmodule IM.Delivery.OutboundQueue do
  @moduledoc """
  单连接 WebSocket 出站调度：WFQ + 老化，防低优先饿死。

  ## 示例

      OutboundQueue.enqueue(pid, %{
        priority: :high,
        inbox_seq: 100,
        packet_binary: bin,
        enqueued_at_ms: System.system_time(:millisecond)
      })

      OutboundQueue.drain_writable(pid, socket)
  """

  @type priority_band :: :high | :normal | :low

  @spec enqueue(pid(), map()) :: :ok
  def enqueue(pid, item), do: GenServer.cast(pid, {:enqueue, item})

  @spec drain_writable(pid(), term()) :: :ok
  def drain_writable(pid, socket), do: GenServer.cast(pid, {:drain, socket})

  # 内部：三带队列 + deficit 计数；pick_next/1 实现 WFQ + aging + max_burst
end
```

### 测试要点（P3-09 / Delivery 阶段）

| 场景 | 期望 |
| --- | --- |
| 仅 HIGH 持续入队 | LOW 在 `priority_aging_low_ms` 内仍被写出 |
| HIGH:LOW = 8:1 权重稳态 | LOW 约 1/13 写出份额 |
| 同带 100 条 | 按 `inbox_seq` 升序写出 |
| UI | 客户端按 `conv_seq` 排序，与到达序无关 |
