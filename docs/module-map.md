# 功能模块对照表

本文件是 **设计 ↔ 实现 ↔ 代码 ↔ 协议** 的单页速查，供开发人员与 AI 在改功能时快速定位文档与源码。

> **维护规则**：新增/变更功能模块时，同步更新本表对应行；系统级变更另须更新 [architecture-overview.md](design/architecture-overview.md)。

---

## 如何使用

| 场景 | 阅读顺序 |
| --- | --- |
| 改某个业务能力 | 本表找行 → 读 **设计** → 读 **实现** → 改 **代码** → 跑 **测试** |
| 按 Phase 开发 | [specs-index.md](specs-index.md) → `.kiro/specs/phase-N-*/design.md` → [PROGRESS.md](implementation/elixir/PROGRESS.md) |
| 改协议 / cmd | [protocol.md](design/protocol/protocol.md) + `proto/` → [doc-sync-checklist.md](design/doc-sync-checklist.md) → 本表 → 实现文档 |
| 查 REST 接口 | [http-api-reference.md](implementation/elixir/http-api-reference.md) |
| 查 WS 时序 | [protocol-e2e-message-sequences.md](implementation/elixir/protocol-e2e-message-sequences.md)（E2E 自动生成） |
| 查代码落位 | [project-structure.md](implementation/elixir/project-structure.md) |

---

## 核心路径（厚文档优先）

| 功能 | 设计 | 实现 | Proto | 服务层 / 关键模块 | 主要测试 |
| --- | --- | --- | --- | --- | --- |
| 双通道（WS + REST） | [dual-channel-api](design/dual-channel-api.md) | [dual-channel-api](implementation/elixir/dual-channel-api.md) | `common.proto` | `IM.Application.Dispatch`、`IM.Ingress.Http`、`IM.Protocol.Router` | `dual_channel_rest_test.exs`、`protocol/router_test.exs` |
| 连接鉴权 | [auth](design/auth.md) | [auth](implementation/elixir/auth.md) | `auth.proto` | `IM.Services.Auth`、`IM.Websocket.Commands.Auth` | `auth_test.exs`、`im_client/protocol/auth_guard_test.exs` |
| 发消息 + ACK | [message-send-ack](design/message-send-ack.md) | [message-send-ack](implementation/elixir/message-send-ack.md) | `message.proto` | `IM.Services.Message`、`IM.Websocket.Commands.MsgSend/Ack` | `message_test.exs`、`im_client/protocol/*` |
| 离线拉取 | [offline-pull](design/offline-pull.md) | [offline-pull](implementation/elixir/offline-pull.md) | `sync.proto` | `IM.Services.Offline` | `offline_test.exs` |
| 群聊扇出 | [group](design/group.md) | [group](implementation/elixir/group.md) | `group.proto`、`message.proto` | `IM.Services.Group`、`IM.Cluster.GroupPusher` | `message_group_test.exs`、`group_manage_test.exs` |
| 聊天室 | [room](design/room.md) | [room](implementation/elixir/room.md) | `room.proto` | `IM.Services.Room`、`IM.Room.Pubsub` | `room_test.exs`、`im_client/protocol/room_test.exs` |
| 模块化分层 | [modular-architecture](design/modular-architecture.md) | [modular-architecture](implementation/elixir/modular-architecture.md) | — | 全 `lib/im/` 目录结构 | `skeleton_test.exs` |
| 数据库 / Ecto | [database-design](design/database/database-design.md) | [database](implementation/elixir/database.md) | — | `IM.Repo`、`IM.Schemas.*` | 各 `services/*_test.exs` |
| 可观测性 | [observability](design/observability.md) | [observability](implementation/elixir/observability.md) | — | `IM.Log`、`IM.Telemetry.*` | `log_test.exs`、`metrics_controller_test.exs` |
| Kafka 旁路 | [kafka-event-bus](design/kafka-event-bus.md) | [kafka-event-bus](implementation/elixir/kafka-event-bus.md) | `event.proto` | `IM.EventBus.*` | `event_bus_test.exs` |
| 离线推送 | [mobile-push](design/mobile-push.md) | [mobile-push](implementation/elixir/mobile-push.md) | `event.proto` | `IM.Delivery.MobilePush` | `mobile_push_test.exs` |
| 少拷贝投递 | [zero-copy-delivery](design/zero-copy-delivery.md) | [zero-copy-delivery](implementation/elixir/zero-copy-delivery.md) | — | `IM.Delivery.Router`、`IM.Protocol.Push` | `delivery/router_test.exs` |

---

## 消息与连接

| 功能 | 设计 | 实现 | Proto | 服务层 / 关键模块 | 主要测试 |
| --- | --- | --- | --- | --- | --- |
| 传输 / 封包 | [transport](design/transport.md)、[packet](design/packet.md) | [project-structure](implementation/elixir/project-structure.md) §`lib/pb/` | `common.proto` | `IM.Protocol.Codec`、`IM.Protocol.Reply` | `codec_test.exs`、`reply_test.exs` |
| 命令字 | [cmd-type](design/cmd-type.md) | [protocol-regression-checklist](implementation/elixir/protocol-regression-checklist.md) | `common.proto` | `IM.Protocol.Cmd` | `error_codes_test.exs` |
| 心跳 | [heartbeat](design/heartbeat.md) | [heartbeat](implementation/elixir/heartbeat.md) | `auth.proto` | `IM.Services.Heartbeat` | `im_client/protocol/session_test.exs` |
| 重连 | [reconnect](design/reconnect.md) | [reconnect](implementation/elixir/reconnect.md) | `auth.proto` | `IM.Services.Session` | `session_test.exs` |
| 多端 | [multi-device](design/multi-device.md) | [multi-device](implementation/elixir/multi-device.md) | `auth.proto` | `IM.Services.Session`、`IM.Connection.Registry` | `device_limit_test.exs` |
| 消息模型 | [message-model](design/message-model.md) | [message-model](implementation/elixir/message-model.md) | `message.proto` | `IM.Schemas.MessageBody` | `message_test.exs` |
| 消息上下文 | [message-context](design/message-context.md) | [message-context](implementation/elixir/message-context.md) | — | `IM.Domain.MessageContext` | `dispatch_test.exs` |
| msg_id 发号 | [msg-id-snowflake](design/msg-id-snowflake.md) | [database](implementation/elixir/database.md) | — | `IM.Services.MsgId` | `msg_id_lease_test.exs` |
| 已读回执 | [read-receipt](design/read-receipt.md) | [read-receipt](implementation/elixir/read-receipt.md) | `message.proto` | `IM.Services.MessageRead` | `message_read_test.exs` |
| 未读数 | [unread-count](design/unread-count.md) | [unread-count](implementation/elixir/unread-count.md) | — | `IM.Conversation.UnreadCache` | `unread_count_test.exs` |
| 撤回 | [recall](design/recall.md) | [recall](implementation/elixir/recall.md) | `message.proto` | `IM.Services.MessageRecall` | `message_extensions_test.exs` |
| 编辑 | [edit](design/edit.md) | [edit](implementation/elixir/edit.md) | `message.proto` | `IM.Services.MessageEdit` | `extensions_test.exs` |
| 阅后即焚 | [burn-after-read](design/burn-after-read.md) | [burn-after-read](implementation/elixir/burn-after-read.md) | `message.proto` | `IM.Jobs.MessageBurn` | `msg_burn_test.exs` |
| 透传 | [passthrough](design/passthrough.md) | [passthrough](implementation/elixir/passthrough.md) | `passthrough.proto` | `IM.Services.Passthrough` | `im_client/protocol/*` |
| 流式消息 | [stream-message](design/stream-message.md) | [stream-message](implementation/elixir/stream-message.md) | `message.proto` | `IM.Services.StreamManager` | `stream_test.exs` |
| Payload 压缩 | [payload-compression](design/payload-compression.md) | [payload-compression](implementation/elixir/payload-compression.md) | `common.proto` | `IM.Protocol.Compression` | `compression_test.exs` |
| TTL 清理 | [message-ttl-cleanup](design/message-ttl-cleanup.md) | [database](implementation/elixir/database.md) | — | `IM.Jobs.TtlPurge` | — |

---

## 社交与管理

| 功能 | 设计 | 实现 | Proto | 服务层 / 关键模块 | 主要测试 |
| --- | --- | --- | --- | --- | --- |
| 好友 | [friend](design/friend.md) | [friend](implementation/elixir/friend.md) | `friend.proto` | `IM.Services.Friend` | `friend_test.exs` |
| 群组管理 | [group](design/group.md) | [group](implementation/elixir/group.md) | `group.proto` | `IM.Services.Group` | `group_manage_test.exs` |
| 聊天室管理 | [room](design/room.md) | [room](implementation/elixir/room.md) | `room.proto` | `IM.Services.Room` | `room_test.exs` |
| 应用通道 | [app-channel](design/app-channel.md) | [app-channel](implementation/elixir/app-channel.md) | `channel.proto` | `IM.Services.Channel` | `channel_test.exs` |
| 权限缓存 | [permission-cache](design/permission-cache.md) | [permission-cache](implementation/elixir/permission-cache.md) | — | `IM.Permission.*` | `block_cache_test.exs`、`mute_cache_test.exs` |

---

## 基础设施与横切

| 功能 | 设计 | 实现 | Proto | 服务层 / 关键模块 | 主要测试 |
| --- | --- | --- | --- | --- | --- |
| 认证模块 | [auth-module](design/auth-module.md) | [auth-module](implementation/elixir/auth-module.md) | `auth.proto` | `IM.Auth.*` | `auth/token_cache_test.exs` |
| 依赖抽象 | [dependency-abstraction](design/dependency-abstraction.md) | [dependency-abstraction](implementation/elixir/dependency-abstraction.md) | — | `IM.Cache`、`IM.Stores.*` | 各 Behaviour 测试 |
| 集群 | [system-design](design/system-design.md) §集群 | [modular-architecture](implementation/elixir/modular-architecture.md) | — | `IM.Cluster.*` | `cluster_test.exs`、`peer_boot_test.exs` |

---

## 客户端 / 工具 / 前端

| 组件 | 设计 | 实现 | 代码路径 | App README |
| --- | --- | --- | --- | --- |
| 协议客户端库 | [test-client](design/test-client.md) | [test-client](implementation/elixir/test-client.md) | `apps/elixir/im_client/` | [im_client README](../apps/elixir/im_client/README.md) |
| Web 演示控制台 | [web-console](design/web-console.md) | [web-console](implementation/web/web-console.md) | `apps/web/im-console/` | [im-console README](../apps/web/im-console/README.md) |
| 压测服务 | [test-client](design/test-client.md) §6 | [loadtest-report](implementation/elixir/loadtest-report.md) | `apps/elixir/loadtest/` | [loadtest README](../apps/elixir/loadtest/README.md) |
| IM 主服务 | [architecture-overview](design/architecture-overview.md) | [implementation/elixir/](implementation/elixir/) | `apps/elixir/im/` | [im README](../apps/elixir/im/README.md) |

应用总览：[apps/README.md](../apps/README.md)

---

## 运维 / 验收 / 质量

| 主题 | 文档 | 常用命令 |
| --- | --- | --- |
| 本地开发踩坑 | [local-dev-gotchas](implementation/elixir/local-dev-gotchas.md) | `mise run pg-forward`、`PGPORT=15432` |
| Release 部署验收 | [release-deploy-test](implementation/elixir/release-deploy-test.md) | `mise run release-deploy`、`release-smoke` |
| 消息冒烟 | [release-smoke-messaging](implementation/elixir/release-smoke-messaging.md) | `mise run release-smoke-messaging` |
| 鉴权冒烟 | [release-smoke-auth](implementation/elixir/release-smoke-auth.md) | — |
| 生产部署指南 | [deploy-guide](implementation/elixir/deploy-guide.md) | — |
| 协议 E2E 时序 | [protocol-e2e-message-sequences](implementation/elixir/protocol-e2e-message-sequences.md) | `mix test.trace` |
| 协议回归清单 | [protocol-regression-checklist](implementation/elixir/protocol-regression-checklist.md) | — |
| 压测报告 | [loadtest-report](implementation/elixir/loadtest-report.md) | — |
| 压测稳定性 | [loadtest-stability](implementation/elixir/loadtest-stability.md) | — |
| 故障演练 | [fault-drill](implementation/elixir/fault-drill.md) | — |
| 差距审查 | [gap-review](implementation/elixir/gap-review.md)、[wave3](implementation/elixir/gap-review-wave3.md) | — |
| 生产部署指南 | [deploy-guide](implementation/elixir/deploy-guide.md) |
| Release 部署验收 | [release-deploy-test](implementation/elixir/release-deploy-test.md) |
| K8s 清单操作 | [deploy/elixir/im/k8s/README.md](../deploy/elixir/im/k8s/README.md) |
| 故障演练 | [fault-drill](implementation/elixir/fault-drill.md) |
| HTTP API 全量 | [http-api-reference](implementation/elixir/http-api-reference.md) | — |

---

## 活索引（状态变更时维护）

| 文档 | 用途 |
| --- | --- |
| [design-decisions.md](design-decisions.md) | 已确认设计模块（DD-xxx） |
| [PROGRESS.md](implementation/elixir/PROGRESS.md) | 实施进度与下一项任务 |
| [architecture-overview.md](design/architecture-overview.md) | 系统架构活文档 |
| [roadmap.md](implementation/elixir/roadmap.md) | 分阶段任务定义 |
| [specs-index.md](specs-index.md) | Kiro 阶段/特性规格（`.kiro/specs/`） |
| [AGENTS.md](../AGENTS.md) | AI / 协作者硬约束 |

---

## 相关链接

- [文档总索引](README.md)
- [设计文档索引](design/README.md)
- [Elixir 实现索引](implementation/elixir/README.md)
