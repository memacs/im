# Kiro Spec 索引

`.kiro/specs/` 存放 **AI 辅助开发时的阶段/特性规格**（requirements → design → tasks），与 [`roadmap.md`](implementation/elixir/roadmap.md) 任务 ID 对齐，**不替代** `proto/` 与 [`protocol.md`](design/protocol/protocol.md)。

> **权威优先级**：`proto/` + `protocol.md` > `AGENTS.md` > `roadmap.md` > Kiro spec > 实现代码  
> **活状态**：任务是否完成以 [`PROGRESS.md`](implementation/elixir/PROGRESS.md) 为准；spec 的 `tasks.md` 为开发过程勾选记录。

---

## 何时读 / 写 Spec

| 场景 | 动作 |
| --- | --- |
| 按 roadmap 做新 Phase / 特性 | 先读或写对应 spec 三件套，再写代码（见 [im-implementation Skill](../.agents/skills/im-implementation/SKILL.md)） |
| 查某 Phase 的实现要点 | 读 `design.md`（模块表、流程）；细节仍以 `docs/implementation/elixir/*.md` 为准 |
| 查任务是否做完 | **以 `PROGRESS.md` 为准**；`tasks.md` 勾选为辅助 |
| 新增独立特性（非 roadmap 既有 Phase） | 新建 `.kiro/specs/<feature-id>/` 三件套，并在本索引登记 |

### Spec 三件套格式

```text
.kiro/specs/<id>/
  requirements.md   # 用户故事 + EARS 验收
  design.md         # 模块、流程、API、测试策略
  tasks.md          # 可勾选任务（对齐 roadmap ID）
```

---

## Phase 0–13（主路线图）

与 [`roadmap.md`](implementation/elixir/roadmap.md) 一一对应；Phase 0 无独立 spec（脚手架任务直接在 roadmap / PROGRESS 中跟踪）。

| Phase | 名称 | Spec 目录 | 主要 design / impl 文档 |
| --- | --- | --- | --- |
| 1 | 协议适配层 | [phase-1-protocol-adapter](../.kiro/specs/phase-1-protocol-adapter/) | [project-structure](implementation/elixir/project-structure.md)、[dual-channel-api](implementation/elixir/dual-channel-api.md) |
| 2 | WebSocket 与连接生命周期 | [phase-2-connection-lifecycle](../.kiro/specs/phase-2-connection-lifecycle/) | [auth](implementation/elixir/auth.md)、[heartbeat](implementation/elixir/heartbeat.md) |
| 3 | 单聊消息主路径 | [phase-3-private-message](../.kiro/specs/phase-3-private-message/) | [message-send-ack](implementation/elixir/message-send-ack.md) |
| 4 | 离线同步与收件箱 | [phase-4-offline-pull](../.kiro/specs/phase-4-offline-pull/) | [offline-pull](implementation/elixir/offline-pull.md) |
| 5 | 群聊与扇出 | [phase-5-group-fanout](../.kiro/specs/phase-5-group-fanout/) | [group](implementation/elixir/group.md) |
| 6 | 聊天室 PubSub | [phase-6-chatroom](../.kiro/specs/phase-6-chatroom/) | [room](implementation/elixir/room.md) |
| 7 | 消息扩展命令 | [phase-7-message-extensions](../.kiro/specs/phase-7-message-extensions/) | [recall](implementation/elixir/recall.md)、[edit](implementation/elixir/edit.md)、[burn-after-read](implementation/elixir/burn-after-read.md) 等 |
| 8 | 群 / 室 / 好友管理 | [phase-8-group-room-friend](../.kiro/specs/phase-8-group-room-friend/) | [group](implementation/elixir/group.md)、[room](implementation/elixir/room.md)、[friend](implementation/elixir/friend.md) |
| 9 | 集群、旁路与可观测性 | [phase-9-cluster-observability](../.kiro/specs/phase-9-cluster-observability/) | [observability](implementation/elixir/observability.md)、[kafka-event-bus](implementation/elixir/kafka-event-bus.md) |
| 10 | 压测与上线准备 | [phase-10-loadtest-ops](../.kiro/specs/phase-10-loadtest-ops/) | [loadtest-report](implementation/elixir/loadtest-report.md)、[deploy-guide](implementation/elixir/deploy-guide.md) |
| 11 | 应用通道 | [phase-11-app-channel](../.kiro/specs/phase-11-app-channel/) | [app-channel](implementation/elixir/app-channel.md) |
| 12 | Web 演示控制台 | [phase-12-web-console](../.kiro/specs/phase-12-web-console/) | [web-console](implementation/web/web-console.md) |
| 13 | 缓存 / 未读 / Remediation | 见下方 **Remediation** 与 [gap-review](implementation/elixir/gap-review.md) | [unread-count](implementation/elixir/unread-count.md)、[permission-cache](implementation/elixir/permission-cache.md) |

---

## 子项目 Spec

| 组件 | Spec 目录 | 说明 |
| --- | --- | --- |
| im_client（C0–C1） | [im-client-c0-c1](../.kiro/specs/im-client-c0-c1/) | 协议客户端库骨架与鉴权 MVP |
| 协议 E2E trace | [protocol-e2e-im-client](../.kiro/specs/protocol-e2e-im-client/) | E2E 时序导出与 trace 覆盖 |

---

## 特性补全 Spec（跨 Phase）

| Spec 目录 | 对齐任务 / 主题 | 相关文档 |
| --- | --- | --- |
| [dual-channel-completion](../.kiro/specs/dual-channel-completion/) | REST 与 Dispatch 补全 | [dual-channel-api](design/dual-channel-api.md) |
| [p7-08-p8-09](../.kiro/specs/p7-08-p8-09/) | P7-08 流式消息、P8-09 相关 | [stream-message](implementation/elixir/stream-message.md) |
| [design-gaps-completion](../.kiro/specs/design-gaps-completion/) | 设计文档与实现差距补全 | [gap-review](implementation/elixir/gap-review.md) |
| [brod-producer](../.kiro/specs/brod-producer/) | Kafka Brod Producer 接入 | [kafka-event-bus](implementation/elixir/kafka-event-bus.md) |

---

## Remediation / 对齐 Wave

Phase 9–13 及 gap-review 期间的 **专项修复与对齐** spec；完成后以 PROGRESS / gap-review 文档为准。

| Wave | Spec 目录 | 主题（摘要） |
| --- | --- | --- |
| review-debt **wave1** | [review-debt-wave1](../.kiro/specs/review-debt-wave1/) | MsgId 租约、Cache 扩展、Encoder、push_token、loadtest 修正 |
| review-debt **wave2** | [review-debt-wave2](../.kiro/specs/review-debt-wave2/) | 差距审查 wave2 项 |
| review-debt **wave3** | [review-debt-wave3](../.kiro/specs/review-debt-wave3/) | 差距审查 wave3 项 |
| review-debt **wave4** | [review-debt-wave4](../.kiro/specs/review-debt-wave4/) | 差距审查 wave4 项 |
| review-debt **wave5** | [review-debt-wave5](../.kiro/specs/review-debt-wave5/) | 差距审查 wave5 项 |
| review-debt **wave6** | [review-debt-wave6](../.kiro/specs/review-debt-wave6/) | 差距审查 wave6 项 |
| observability **wave1** | [observability-align-wave1](../.kiro/specs/observability-align-wave1/) | 可观测性对齐 wave1 |
| observability **wave2** | [observability-align-wave2](../.kiro/specs/observability-align-wave2/) | 可观测性对齐 wave2 |
| observability **wave3** | [observability-align-wave3](../.kiro/specs/observability-align-wave3/) | 可观测性对齐 wave3 |
| observability **wave4** | [observability-align-wave4](../.kiro/specs/observability-align-wave4/) | 可观测性对齐 wave4 |
| observability **wave5** | [observability-align-wave5](../.kiro/specs/observability-align-wave5/) | 可观测性对齐 wave5 |

差距审查汇总：[gap-review.md](implementation/elixir/gap-review.md)、[wave3](implementation/elixir/gap-review-wave3.md)

---

## 文档关系图

```text
proto/ + protocol.md          ← 行为契约（最高）
        ↓
docs/design/*.md              ← 设计意图（为什么）
        ↓
roadmap.md + PROGRESS.md      ← 阶段任务与活状态
        ↓
.kiro/specs/*/                ← AI 开发时的 requirements/design/tasks
        ↓
docs/implementation/elixir/*  ← 实现说明（怎么做）
        ↓
apps/elixir/im/lib/           ← 源码
```

功能模块与代码对照另见 [module-map.md](module-map.md)。

---

## 相关链接

- [文档总索引](README.md)
- [功能模块对照表](module-map.md)
- [roadmap](implementation/elixir/roadmap.md)
- [PROGRESS](implementation/elixir/PROGRESS.md)
- [im-implementation Skill](../.agents/skills/im-implementation/SKILL.md)
- [AGENTS.md](../AGENTS.md)（含 §文档地图）
