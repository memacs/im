# Elixir 实现文档

基于 Elixir + Phoenix Framework 的 IM 服务端实现。

> **当前状态**：**Phase 0 完成**。Phoenix 骨架、分层占位模块、protobuf 代码生成（`lib/pb/`）就位，
> Release 镜像可构建、K8s 在 PSS restricted 下可 rollout、健康检查与 `bin/migrate` 通过。
> 进度见 [PROGRESS.md](PROGRESS.md)（下一项 Phase 1 协议适配层）。

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
mise run k8s-up        # 本地 postgres + redis（mix test 需要 postgres）
kubectl -n im-dev port-forward svc/postgres 5432:5432   # 另开终端
mise run ci            # proto + format + compile + test
```

详见根 [README.md](../../../README.md)。

---

## 实施阶段

| Phase | 名称 | 状态 |
|-------|------|------|
| 0 | 工程脚手架 | **完成（10/10）** |
| 1 | 协议适配层 | 待开始（0/5，骨架模块已就位） |
| 2 | WebSocket 接入 | 待开始（0/14） |
| 3+ | … | 见 [roadmap.md](roadmap.md) |

---

## 相关链接

- [协议设计](../design/protocol/protocol.md)
- [数据库设计](../design/database/database-design.md)
- [AI 协作约定](../../../agent.md)
- [Agent Skills 索引（Elixir/Phoenix、Redis、Kubernetes：`kubernetes-skill`）](../../../.agents/skills/README.md)
