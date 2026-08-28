# 自动化测试客户端 - Elixir 实现

| 项 | 内容 |
|------|------|
| 语言 | Elixir |
| 设计文档 | [test-client.md](../../design/test-client.md)（**权威**） |
| Roadmap | Phase 2+ 集成测试；[release-deploy-test.md](release-deploy-test.md) 冒烟 |

> **文档分级**：边缘模块 impl。状态机与 API 见设计文档；本文仅列模块与测试要点。

---

## 模块

| 模块 | 职责 |
| --- | --- |
| `IM.TestClient` | 测试用 WS 客户端：连接、鉴权、发 `Packet`、收 PUSH |
| `IM.TestClient.Assertions` | 断言 `seq`/`cmd`/payload；等待 `CMD_MSG_PUSH` |
| `IM.TestClient.REST` | 可选：REST 发消息/拉取，与 WS 场景对照 |

放置于 `test/support/`，**不**打入 Release。

---

## 测试要点

- 连接 → `AUTH_REQ` → `AUTH_RESP` → `HEARTBEAT` 最小路径可自动化。
- `CMD_MSG_SEND` 后同步收到 `ACK_DOWN(SERVER_RECEIVED)`。
- 双通道：同一场景 WS + REST 客户端各跑一遍（见 [dual-channel-api.md](dual-channel-api.md) §7）。
- K8s 冒烟：`release-smoke` 脚本可调用 TestClient 或等价脚本。

---

## 参考

- Phoenix 集成测试：`IMWeb.ConnCase` + 二进制 WebSocket 客户端库（如 `WebSockex` 测试封装）。
