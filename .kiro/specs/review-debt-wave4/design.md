# Design — Review Debt Wave4

## L1

```text
key examples:
  {:block, app, blocker, blocked} -> {bool, expire_ms}
  {:mute, app, group, user} -> {bool, expire_ms}
  {:device_ban, app, user, device} -> {bool, expire_ms}

PubSub topic: "im:permission:invalidate"
payload: {:block, app, blocker} | {:mute, app, group} | {:device_ban, app, user, device}
```

`Invalidator` 为常驻 GenServer，`handle_info` 调 `L1.invalidate/1`。

## OutboundQueue

纯数据结构（挂在 PacketTransport state），非独立 GenServer：

- `enqueue/2` / `drain/2` → `{[binary], queue}`
- deficit WFQ；aging 升档；burst 强制换带；超 `outbound_max_depth` 丢最旧 LOW
