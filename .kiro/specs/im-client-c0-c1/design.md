# Design: im_client C0/C1

## 组件

| 模块 | 职责 |
| --- | --- |
| `IM.Client.Error` | 轻量错误结构（不依赖 `IM.Domain.Error`） |
| `IM.Client.Protocol.Codec` | Packet / payload 编解码 + `ver` 门禁 |
| `IM.Client.Transport` | WebSockex 二进制帧，消息回传 Connection |
| `IM.Client.Connection` | GenServer 状态机 + seq 分配 + Inbox |
| `IM.Client.Assertions` | `await_cmd` / `await_seq` 辅助 |
| `IM.Client.REST` | Req：`POST /api/v1/sessions` |
| `IM.Client` | 薄门面：start/connect/authenticate/… |

## 状态机

```
disconnected → connecting → connected → authenticating → authenticated
                 ↓              ↓              ↓              ↓
              disconnected ← ← ← ← ← ← ← ← ← ← ← ← disconnecting
```

## 测试策略

- Codec：纯单元，向量与 `im` Codec 语义对齐。
- Connection：注入 FakeTransport，模拟帧入站。
- REST / 真 WS：可选；压测联调时对运行中的 `im` 验证。

## Proto 同步

`mise run proto-gen` 生成到 `apps/elixir/im/lib/pb/` 后 **rsync** 到 `apps/elixir/im_client/lib/pb/`；`proto-gen-check` 同时校验两处。
