# 消息投递少拷贝 - Elixir 实现

| 项 | 内容 |
|------|------|
| 语言 | Elixir |
| 设计文档 | [zero-copy-delivery.md](../../design/zero-copy-delivery.md) |
| 相关 | [message-send-ack.md](message-send-ack.md) §17 预编码、[kafka-event-bus.md](kafka-event-bus.md) |

---

## 1. BEAM 二进制语义（必读）

| 机制 | 说明 |
|------|------|
| **Ref-counted heap binary** | `> 64` 字节的 binary 在堆外共享；多进程传递 **同一份引用**（同节点 `send`） |
| **Sub-binary** | `binary_part/3` 切片不拷贝父 binary |
| **跨节点 send** | 远程节点 **必定拷贝** 一份 |
| **`:binary.copy/1`** | 仅当子 binary 长期持有导致 **大 binary 无法释放** 时使用 |

实现时：**扇出传 `packet_binary`，不传 struct**。

---

## 2. Codec 分层

```elixir
defmodule IM.Protocol.Codec do
  @doc "热路径：只解包头 + 保留 payload bytes"
  def decode_frame(frame) when is_binary(frame) do
    with {:ok, header, rest} <- decode_header(frame) do
      {:ok, %Packet{header | payload: rest}}
    end
  end

  @doc "仅业务 Handler 调用一次"
  def decode_payload(%Packet{payload: bin}, module) do
    module.decode(bin)
  end
end
```

**禁止**在 `Router` → `Hook` → `Handler` 链上多次 `decode_payload`。

---

## 3. 下行：编码一次 + 二进制扇出

与 [zero-copy-delivery.md](zero-copy-delivery.md) 设计一致，落地约定：

```elixir
defmodule IM.Delivery.Pusher do
  @spec encode_push_packet(IM.Domain.Message.t(), keyword()) :: binary()
  def encode_push_packet(message, opts \\ []) do
    payload = ChatMessage.encode(message)

    packet = %Packet{
      ver: 1,
      cmd: :CMD_MSG_PUSH,
      seq: 0,
      ts: System.system_time(:millisecond),
      trace_id: Keyword.get(opts, :trace_id, ""),
      route_key: message.conv_id,
      payload: payload
    }

    Packet.encode(packet)
  end
end
```

```elixir
# 扇出：传递 binary，不传递 %ChatMessage{}
def deliver_targets(targets, packet_binary, msg_id) do
  Enum.each(targets, fn %{pid: pid, node: node} ->
  if node == node() do
    send(pid, {:push_binary, packet_binary, msg_id})
  else
    :erlang.send({pid, node}, {:push_binary, packet_binary, msg_id})
  end
  end)
end
```

```elixir
# UserSocket：直接写出，不再 encode
def handle_info({:push_binary, packet_binary, _msg_id}, socket) do
  {:noreply, push(socket, "binary", packet_binary)}
end
```

### 3.1 聊天室 PubSub

```elixir
Phoenix.PubSub.broadcast(
  IM.PubSub,
  room_topic(room_id),
  {:room_push, packet_binary, exclude: {from_uid, from_device_id}}
)
```

订阅侧 **原样** `push(socket, "binary", packet_binary)`。

---

## 4. 落库与复用

```elixir
# 写入：content 为 PB bytes（已在 enrich 时 encode 一次）
%Message{content: content_bytes, ...}

# 若扇出与落库同一请求：复用同一 content_bytes 构造 ChatMessage，避免 DB 读出再 decode
def insert_and_fanout(req, content_bytes, ctx) do
  with {:ok, msg} <- MessageStore.insert(%{content: content_bytes, ...}) do
    packet_binary = Pusher.encode_push_packet(%{msg | content: content_bytes}, trace_id: ctx.trace_id)
    Router.deliver(recipients, packet_binary, msg.msg_id)
    {:ok, msg}
  end
end
```

**禁止**：`Jason.encode!(content)` 入库。

---

## 5. Kafka EventBus

```elixir
def publish_upstream(packet, ctx) do
  event = %UpstreamEvent{
    event_id: Ecto.UUID.generate(),
    app_key: ctx.app_key,
    cmd: packet.cmd,
    payload: packet.payload  # 透传，不 decode
  }

  IM.EventBus.Buffer.cast(:upstream, event, partition_key(ctx))
end
```

`DownstreamEvent` / `PushNotificationBatchEvent` 同理：`display` 在 enrich 时生成，**不要**为 Kafka 再 `ChatMessage.decode(content)`。

---

## 6. 离线 `im.push`

```elixir
# enrich 阶段一次性生成
{display, content_bytes} = PushDisplay.build_from_req(req)

# MobilePush 扇出结束后写批量事件
IM.EventBus.publish(:push, %PushNotificationBatchEvent{
  display: display,
  payload: content_bytes,
  targets: targets
})
```
```

---

## 7. 反模式对照

```elixir
# ❌ 每用户编码
Enum.each(users, fn u ->
  push(u, Packet.encode(build_packet(message)))
end)

# ✅
packet_binary = Pusher.encode_push_packet(message)
Enum.each(users, fn u -> deliver(u, packet_binary) end)
```

```elixir
# ❌ Kafka JSON 包裹
Jason.encode!(%{payload: Base.encode64(packet.payload)})

# ✅
UpstreamEvent.encode(%UpstreamEvent{payload: packet.payload})
```

```elixir
# ❌ 大 binary 泄漏（极端：小 sub-binary 引用 4MB 父 binary）
tiny = :binary.part(huge_packet, 0, 8)
# 长期 GenServer state 只存 tiny → 考虑 :binary.copy(tiny)
```

---

## 8. 测试与 Profile

```elixir
test "fanout encodes packet once" do
  expect(IM.Protocol.Packet, :encode, 1, fn _ -> "bin" end)
  Router.deliver_1000_users(message, ctx)
end
```

```elixir
# mix run -e ':eprof.start; ...; :eprof.analyze()'
# 确认热路径无 Jason.encode!/decode 重复出现
```

---

## 9. Code Review 清单

- [ ] 扇出函数签名是否接收 `packet_binary :: binary()`？
- [ ] Kafka `payload` 是否透传 bytes？
- [ ] DB `content` 是否 BYTEA / `:binary`？
- [ ] Hook 是否重复 decode？
- [ ] 跨节点是否避免「每用户一条跨节点消息」可改为「每边缘节点一条」？
- [ ] 生产日志是否避免打印完整 payload？

---
