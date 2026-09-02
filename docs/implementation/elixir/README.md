# Elixir 实现文档

基于 Elixir + Phoenix Framework 的 IM 服务端实现。

> **当前状态**：**Phase 0–13 完成**。进度与差距审查见 [PROGRESS.md](PROGRESS.md)、[gap-review.md](gap-review.md)。

---

## 活索引（优先读这些）

| 文档 | 用途 |
|------|------|
| [http-api-reference.md](http-api-reference.md) | **HTTP REST 逐接口文档**（参数 + curl 示例） |
| [PROGRESS.md](PROGRESS.md) | **任务状态看板**（做到哪、下一项） |
| [module-map.md](../../module-map.md) | **功能 ↔ 设计 ↔ 代码 ↔ 测试** 单页对照 |
| [specs-index.md](../../specs-index.md) | **Kiro Spec 索引**（`.kiro/specs/` 阶段规格） |
| [roadmap.md](roadmap.md) | 分阶段任务与验收 |
| [project-structure.md](project-structure.md) | `apps/elixir/im/lib/` 模块树 |
| [application-startup.md](application-startup.md) | **OTP 启动顺序与 `IM.Supervisor` 监督树** |
| [monorepo-layout.md](../monorepo-layout.md) | **单仓 apps + deploy 布局（权威）** |
| [design-decisions.md](../../design-decisions.md) | 已确认设计模块索引 |

---

## 技术栈

| 组件 | 版本 | 说明 |
|------|------|------|
| Erlang/OTP | 28.1 | Elixir 运行时（与根 `mise.toml` 一致） |
| Elixir | 1.19.5-otp-28 | 服务端主语言 |
| Phoenix | 1.8 | Web 框架（已引入） |
| Bandit | 1.7 | HTTP / WebSocket 服务器（已引入） |
| Ecto SQL + Postgrex | 3.13 | PostgreSQL 持久化（已引入） |
| Phoenix.PubSub | 2.x | 跨节点消息广播（已引入） |
| Phoenix.Tracker | - | 用户连接定位（Phase 5 接入） |
| libcluster | - | 多节点自动发现（Phase 9 接入） |
| Redix | - | Redis 客户端（Phase 9 接入） |
| Broadway | - | Kafka 消费（Phase 9 接入） |

---

## 文档分级

### 核心路径（厚文档 — 实施时细读）

| 文档 | 说明 |
|------|------|
| [dual-channel-api.md](dual-channel-api.md) | WS + REST、Dispatch、Ingress |
| [auth.md](auth.md) | 连接鉴权、状态机、设备限制 |
| [message-send-ack.md](message-send-ack.md) | 发消息主路径、同步 ACK |
| [database.md](database.md) | Ecto、迁移、分片约定 |
| [modular-architecture.md](modular-architecture.md) | Services + Delivery 分层 |
| [mobile-push.md](mobile-push.md) | 离线 `im.push` |
| [zero-copy-delivery.md](zero-copy-delivery.md) | 预编码扇出 |
| [outbound-queue-scheduling.md](outbound-queue-scheduling.md) | **出站调度详解（WFQ 三带 + 老化 + 合并 + 丢弃策略）**，OutboundQueue + PacketTransport |
| [release-deploy-test.md](release-deploy-test.md) | Release → K8s → 冒烟 |
| [release-smoke-messaging.md](release-smoke-messaging.md) | Release 消息/会话未读冒烟 |

### 基础设施（Phase 9+ 厚文档）

| 文档 | 说明 |
|------|------|
| [observability.md](observability.md) | 指标、日志、埋点 |
| [kafka-event-bus.md](kafka-event-bus.md) | Kafka 旁路五 Topic |
| [permission-cache.md](permission-cache.md) | 拉黑/禁言/封禁热缓存 |
| [payload-compression.md](payload-compression.md) | WS payload 压缩协商 |

### 运维 / 部署 / 验收

| 文档 | 说明 |
|------|------|
| [local-dev-gotchas.md](local-dev-gotchas.md) | 本地 Postgres 15432、CI 端口 |
| [deploy-guide.md](deploy-guide.md) | 生产部署指南 |
| [flamegraph.md](flamegraph.md) | CPU 火焰图（`mise run flamegraph`） |
| [release-smoke-auth.md](release-smoke-auth.md) | Release 鉴权冒烟 |
| [fault-drill.md](fault-drill.md) | 故障演练步骤 |

### 测试 / 协议验收

| 文档 | 说明 |
|------|------|
| [protocol-e2e-message-sequences.md](protocol-e2e-message-sequences.md) | E2E 时序（自动生成，勿手改） |
| [protocol-regression-checklist.md](protocol-regression-checklist.md) | 协议回归清单 |
| [test-client.md](test-client.md) | im_client 库实现说明 |

### 压测

| 文档 | 说明 |
|------|------|
| [loadtest-report.md](loadtest-report.md) | 压测报告与指标 |
| [loadtest-stability.md](loadtest-stability.md) | 长时间稳定性跑法 |

### 差距审查

| 文档 | 说明 |
|------|------|
| [gap-review.md](gap-review.md) | 差距审查与 Remediation |
| [gap-review-wave3.md](gap-review-wave3.md) | Wave3 生产就绪项 |

### 边缘模块（薄文档 — 模块表 + 测试要点 + 链设计）

| 文档 | 设计文档 |
|------|----------|
| [heartbeat.md](heartbeat.md) | [design/heartbeat.md](../../design/heartbeat.md) |
| [reconnect.md](reconnect.md) | [design/reconnect.md](../../design/reconnect.md) |
| [message-model.md](message-model.md) | [design/message-model.md](../../design/message-model.md) |
| [message-context.md](message-context.md) | [design/message-context.md](../../design/message-context.md) |
| [offline-pull.md](offline-pull.md) | [design/offline-pull.md](../../design/offline-pull.md) |
| [read-receipt.md](read-receipt.md) | [design/read-receipt.md](../../design/read-receipt.md) |
| [recall.md](recall.md) | [design/recall.md](../../design/recall.md) |
| [edit.md](edit.md) | [design/edit.md](../../design/edit.md) |
| [burn-after-read.md](burn-after-read.md) | [design/burn-after-read.md](../../design/burn-after-read.md) |
| [passthrough.md](passthrough.md) | [design/passthrough.md](../../design/passthrough.md) |
| [stream-message.md](stream-message.md) | [design/stream-message.md](../../design/stream-message.md) |
| [group.md](group.md) | [design/group.md](../../design/group.md) |
| [room.md](room.md) | [design/room.md](../../design/room.md) |
| [friend.md](friend.md) | [design/friend.md](../../design/friend.md) |
| [app-channel.md](app-channel.md) | [design/app-channel.md](../../design/app-channel.md) |
| [multi-device.md](multi-device.md) | [design/multi-device.md](../../design/multi-device.md) |
| [unread-count.md](unread-count.md) | [design/unread-count.md](../../design/unread-count.md) |
| [auth-module.md](auth-module.md) | [design/auth-module.md](../../design/auth-module.md) |
| [dependency-abstraction.md](dependency-abstraction.md) | [design/dependency-abstraction.md](../../design/dependency-abstraction.md) |

---

## 开发环境

```bash
mise install
mise run k8s-up             # 本地 postgres + redis
mise run pg-forward         # 另开终端：Postgres → localhost:15432
mise run ci                 # proto + format + compile + test
```

详见 [local-dev-gotchas.md](local-dev-gotchas.md) 与根 [README.md](../../../README.md)。

---

## 实施阶段

| Phase | 名称 | 状态 |
|-------|------|------|
| 0–12 | 核心协议与集群 | **完成**（见 [PROGRESS.md](PROGRESS.md)） |
| 13 | 缓存/未读/会话/Remediation | **完成** |
| 后续 | 规模实测、v1 deferred | 见 [roadmap.md](roadmap.md)、[gap-review.md](gap-review.md) |

---

## 相关链接

- [文档总索引](../../README.md)
- [功能模块对照表](../../module-map.md)
- [协议设计](../../design/protocol/protocol.md)
- [数据库设计](../../design/database/database-design.md)
- [AI 协作约定](../../../AGENTS.md)
- [Agent Skills 索引](../../../.agents/skills/README.md)
