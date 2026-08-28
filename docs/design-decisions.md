# 协议设计决策索引

本文件是**已评审模块的索引**，不展开长文。  
「为什么这样设计 / 有什么好处」写在 [`design/`](design/) 下各模块独立文档中。

规范细节以 [`design/protocol/protocol.md`](design/protocol/protocol.md) 与 [`proto/`](../proto/) 为准。

**维护规则**（与 `agent.md` 一致）：

0. **协议为准**：所有实现代码以 `proto/` + `protocol.md` 为唯一行为契约；**修改协议须人工确认**（见 `agent.md`「协议为准」「修改协议工作流」）。
1. 某一块协议经讨论确认后，必须新建或更新 `docs/design/<module>.md`（设计意图全文）。
2. 同步：`protocol.md` 对应节只保留规范约定 + 指向该设计文档的链接；本文件一览表改状态；`proto` 注释一致。
3. 未确认模块保持「待评审」，允许继续改。
4. 推翻已确认决策：改 proto + protocol + 对应 `design/*.md`（变更原因写在 PR / commit 说明中，文档内不维护修订历史表）。
5. **系统级变更**须同步更新 [architecture-overview.md](design/architecture-overview.md)（模块、数据流、能力边界；见 `agent.md`）。
6. **功能行为变更**须同步更新该模块文档中的 **`## 完整流程`** Mermaid 图（见 [design/README.md](design/README.md)）。

---

## 决策编号（DD-xxx）

| 编号 | 模块 | 设计文档 |
| --- | --- | --- |
| DD-001 | 传输与序列化 | [transport.md](design/transport.md) |
| DD-003 | 通用封包 Packet | [packet.md](design/packet.md) |
| DD-004 | 命令字 CmdType | [cmd-type.md](design/cmd-type.md) |
| DD-005 | 连接与鉴权 | [auth.md](design/auth.md) |
| DD-006 | 心跳 | [heartbeat.md](design/heartbeat.md) |
| DD-007 | 消息模型 | [message-model.md](design/message-model.md) |
| DD-008 | 发消息与 ACK | [message-send-ack.md](design/message-send-ack.md) |
| DD-009 | 撤回 | [recall.md](design/recall.md) |
| DD-010 | 编辑消息 | [edit.md](design/edit.md) |
| DD-011 | 离线拉取 | [offline-pull.md](design/offline-pull.md) |
| DD-012 | 透传 | [passthrough.md](design/passthrough.md) |
| DD-013 | 多端同步 | [multi-device.md](design/multi-device.md) |
| DD-014 | 已读回执 | [read-receipt.md](design/read-receipt.md) |
| DD-015 | 未读数管理 | [unread-count.md](design/unread-count.md) |
| DD-016 | 重连与恢复 | [reconnect.md](design/reconnect.md) |
| DD-017 | 群组管理 | [group.md](design/group.md) |
| DD-018 | 聊天室管理 | [room.md](design/room.md) |
| DD-019 | 流式消息 | [stream-message.md](design/stream-message.md) |
| DD-020 | 好友系统 | [friend.md](design/friend.md) |
| DD-021 | 依赖抽象层 | [dependency-abstraction.md](design/dependency-abstraction.md) |
| DD-022 | 消息上下文 | [message-context.md](design/message-context.md) |
| DD-023 | 测试客户端 | [test-client.md](design/test-client.md) |
| DD-024 | 模块化架构 | [modular-architecture.md](design/modular-architecture.md) |
| DD-027 | 认证模块架构 | [auth-module.md](design/auth-module.md) |
| DD-028 | 可观测性 | [observability.md](design/observability.md) |
| DD-029 | Kafka 事件总线 | [kafka-event-bus.md](design/kafka-event-bus.md) |
| DD-030 | 离线设备系统推送 | [mobile-push.md](design/mobile-push.md) |
| DD-031 | 双通道 API | [dual-channel-api.md](design/dual-channel-api.md) |
| DD-032 | 消息投递少拷贝 | [zero-copy-delivery.md](design/zero-copy-delivery.md) |
| DD-033 | 权限状态热缓存 | [permission-cache.md](design/permission-cache.md) |
| DD-034 | Packet.payload 压缩协商 | [payload-compression.md](design/payload-compression.md) |
| DD-035 | 应用通道（App Channel） | [app-channel.md](design/app-channel.md) |
| DD-036 | 阅后即焚 | [burn-after-read.md](design/burn-after-read.md) |
| DD-037 | Web 演示控制台（独立前端） | [web-console.md](design/web-console.md) |
| DD-038 | 协议为准、变更须人工确认 | [agent.md](../agent.md)（硬约束「协议为准」） |
| DD-039 | `msg_id` Snowflake 发号 | [msg-id-snowflake.md](design/msg-id-snowflake.md) |
| DD-040 | 消息 TTL 清理 Job | [message-ttl-cleanup.md](design/message-ttl-cleanup.md) |

> DD-002、DD-025、DD-026 预留。新增决策使用下一可用编号，**禁止复用**。

---

## 已确认一览

| 模块 | 状态 | 设计文档 | protocol |
| --- | --- | --- | --- |
| 传输与序列化 | 已确认 | [design/transport.md](design/transport.md) | §1 |
| 通用封包 Packet（含分层与错误模型） | 已确认 | [design/packet.md](design/packet.md) | §2–§3 |
| 命令字 CmdType | 已确认 | [design/cmd-type.md](design/cmd-type.md) | §4 |
| 连接与鉴权 | 已确认 | [design/auth.md](design/auth.md) | §5 |
| 心跳 | 已确认 | [design/heartbeat.md](design/heartbeat.md) | §6 |
| 消息模型 | 已确认 | [design/message-model.md](design/message-model.md) | §7 |
| 发消息与 ACK / 批量下行 | 已确认 | [design/message-send-ack.md](design/message-send-ack.md) | §8 |
| 撤回 | 已确认 | [design/recall.md](design/recall.md) | §9 |
| 编辑消息 | 已确认 | [design/edit.md](design/edit.md) | §10 |
| 阅后即焚 | 已确认 | [design/burn-after-read.md](design/burn-after-read.md) | §26 |
| 离线拉取 | 已确认 | [design/offline-pull.md](design/offline-pull.md) | §11 |
| 透传 | 已确认 | [design/passthrough.md](design/passthrough.md) | §12 |
| 多端同步 | 已确认 | [design/multi-device.md](design/multi-device.md) | §13 |
| 已读回执 | 已确认 | [design/read-receipt.md](design/read-receipt.md) | §14 |
| 未读数管理 | 已确认 | [design/unread-count.md](design/unread-count.md) | §15 |
| 重连与恢复 | 已确认 | [design/reconnect.md](design/reconnect.md) | §16 |
| 群组管理 | 已确认 | [design/group.md](design/group.md) | §19 |
| 聊天室管理 | 已确认 | [design/room.md](design/room.md) | §20 |
| 双通道 API（WebSocket + REST） | 已确认 | [design/dual-channel-api.md](design/dual-channel-api.md) | §21 |
| 流式消息 | 已确认 | [design/stream-message.md](design/stream-message.md) | §22 |
| 消息上下文 | 已确认 | [design/message-context.md](design/message-context.md) | §23 |
| 测试客户端 | 已确认 | [design/test-client.md](design/test-client.md) | §24 |
| Web 演示控制台 | 已确认 | [design/web-console.md](design/web-console.md)（**协议能力全覆盖**） | — |
| 协议为准（开发治理） | 已确认 | [agent.md](../agent.md)（DD-038） | — |
| `msg_id` Snowflake 发号 | 已确认 | [msg-id-snowflake.md](design/msg-id-snowflake.md)（DD-039） | — |
| 消息 TTL 清理 Job | 已确认 | [message-ttl-cleanup.md](design/message-ttl-cleanup.md)（DD-040） | — |
| 好友系统 | 已确认 | [design/friend.md](design/friend.md) | §25 |
| 应用通道（App Channel） | 已确认 | [design/app-channel.md](design/app-channel.md) | §27；Phase 11 已落地 |
| 认证模块架构 | 已确认 | [design/auth-module.md](design/auth-module.md) | — |
| 依赖抽象层 | 已确认 | [design/dependency-abstraction.md](design/dependency-abstraction.md) | — |
| 模块化架构 | 已确认 | [design/modular-architecture.md](design/modular-architecture.md) | — |
| 可观测性（指标与日志） | 已确认 | [design/observability.md](design/observability.md) | — |
| Kafka 事件总线 | 已确认 | [design/kafka-event-bus.md](design/kafka-event-bus.md) | — |
| 离线设备系统推送 | 已确认 | [design/mobile-push.md](design/mobile-push.md) | — |
| 消息投递少拷贝 | 已确认 | [design/zero-copy-delivery.md](design/zero-copy-delivery.md) | — |
| 权限状态热缓存（拉黑/禁言/封禁） | 已确认 | [design/permission-cache.md](design/permission-cache.md) | — |
| Packet.payload 压缩协商 | 已确认 | [design/payload-compression.md](design/payload-compression.md) | §3、§5 |
| 错误码表 | 已确认 | [proto/common.proto](../proto/common.proto) `ErrorCode` 枚举；错误模型见 [packet.md](design/packet.md) | §17 |

目录说明见 [design/README.md](design/README.md)。功能模块与代码对照见 [module-map.md](module-map.md)。
