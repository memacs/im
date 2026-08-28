# Elixir 实现文档

基于 Elixir + Phoenix Framework 的 IM 服务端实现。

> **当前状态**：`apps/elixir/im/` 尚无 Mix 项目。进度见 [PROGRESS.md](PROGRESS.md)（下一项 P0-01）。

---

## 活索引（优先读这些）

| 文档 | 用途 |
|------|------|
| [PROGRESS.md](PROGRESS.md) | **任务状态看板**（做到哪、下一项） |
| [roadmap.md](roadmap.md) | 分阶段任务与验收 |
| [monorepo-layout.md](monorepo-layout.md) | **单仓 apps + deploy 布局（权威）** |
| [project-structure.md](project-structure.md) | `apps/elixir/im/lib/` 模块树 |
| [design-decisions.md](../../design-decisions.md) | 已确认设计模块索引 |

---

## 技术栈

| 组件 | 版本 | 说明 |
|------|------|------|
| Erlang/OTP | 28.0 | Elixir 运行时 |
| Elixir | 1.19.5-otp-28 | 服务端主语言 |
| Phoenix | 最新 | Web 框架 |
| Phoenix.PubSub | - | 跨节点消息广播 |
| Phoenix.Tracker | - | 用户连接定位 |
| libcluster | - | 多节点自动发现 |
| Redix | - | Redis 客户端 |
| Broadway | - | Kafka 消费 |

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
| [release-deploy-test.md](release-deploy-test.md) | Release → K8s → 冒烟 |

### 基础设施（Phase 9+ 厚文档）

| 文档 | 说明 |
|------|------|
| [observability.md](observability.md) | 指标、日志、埋点 |
| [kafka-event-bus.md](kafka-event-bus.md) | Kafka 旁路五 Topic |

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
| [test-client.md](test-client.md) | [design/test-client.md](../../design/test-client.md) |

---

## 开发环境

```bash
mise install
mise run proto-check   # 当前可用
# P0-01 后：mise run setup / test / ci
```

详见根 [README.md](../../../README.md)。

---

## 实施阶段

| Phase | 名称 | 状态 |
|-------|------|------|
| 0 | 工程脚手架 | 进行中（4/10，尚无 mix 项目） |
| 1 | 协议适配层 | 待开始 |
| 2 | WebSocket 接入 | 待开始（0/14） |
| 3+ | … | 见 [roadmap.md](roadmap.md) |

---

## 相关链接

- [协议设计](../design/protocol/protocol.md)
- [数据库设计](../design/database/database-design.md)
- [AI 协作约定](../../../agent.md)
- [Agent Skills 索引（Elixir/Phoenix、Redis、Kubernetes：`kubernetes-skill`）](../../../.agents/skills/README.md)
