# 自动化测试客户端 - Elixir 实现

| 项 | 内容 |
|------|------|
| 语言 | Elixir |
| 设计文档 | [test-client.md](../../design/test-client.md)（**权威**） |
| 代码 | `apps/elixir/im_client`（`IM.Client.*`）、`apps/elixir/loadtest`（`IM.LoadTest.*`） |
| Roadmap | im_client C0+；loadtest L0+；[release-deploy-test.md](release-deploy-test.md) 冒烟 |

> **文档分级**：边缘模块 impl。状态机与 API 见设计文档；本文仅列模块与测试要点。

---

## 模块（im_client）

| 模块 | 职责 |
| --- | --- |
| `IM.Client` | 门面：connect / authenticate / heartbeat / send_message |
| `IM.Client.Protocol.Codec` | Packet 编解码（与 `im` 语义对齐） |
| `IM.Client.Connection` | WS 状态机 + Inbox |
| `IM.Client.Transport` | WebSockex 二进制帧 |
| `IM.Client.REST` | `POST /api/v1/sessions` |
| `IM.Client.Assertions` / `Scenario` | 测试辅助，见 `test/support/`（不打进 Release） |

放置于 `apps/elixir/im_client/`，**不**打入 IM Release。`lib/pb/` 由 `mise run proto-gen` 从 `im` 同步。

---

## 模块（loadtest）

| 模块 | 职责 |
| --- | --- |
| `IM.LoadTest.Worker` | 虚拟用户 |
| `IM.LoadTest.Controller` | 并发编排 |
| `IM.LoadTest.Metrics` / `Reporter` | 指标与 JSON 报告 |
| `mix loadtest.run` | CLI |

---

## 测试要点

- Codec round-trip 与 ver 门禁（`mise run im_client:test`）。
- Connection FakeTransport：AUTH → HEARTBEAT。
- 压测：`mix loadtest.run connection_load --app-key …`（需目标 IM 与用户）。

---

## 参考

- Kiro：`.kiro/specs/im-client-c0-c1/`、`.kiro/specs/phase-10-loadtest-ops/`
- [loadtest-report.md](loadtest-report.md)、[deploy-guide.md](deploy-guide.md)
