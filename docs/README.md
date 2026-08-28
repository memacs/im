# IM 系统文档

基于 WebSocket + Protobuf 的即时通讯系统。**协议为准**（`proto/` + [protocol.md](design/protocol/protocol.md)），改协议须人工确认。

---

## 按角色快速入门

### 新加入开发人员

1. [product-overview.md](product-overview.md) — 产品能力与场景
2. [design/architecture-overview.md](design/architecture-overview.md) — **系统架构首读**
3. [implementation/elixir/project-structure.md](implementation/elixir/project-structure.md) — 代码目录与请求路径
4. [implementation/elixir/local-dev-gotchas.md](implementation/elixir/local-dev-gotchas.md) — 本地 Postgres 15432 等踩坑
5. 根 [README.md](../README.md) — `mise run ci` / `release-deploy` 命令

### 实现某个功能

1. [module-map.md](module-map.md) — **功能 ↔ 设计 ↔ 实现 ↔ 代码 ↔ 测试** 单页对照
2. 对应 `docs/design/<module>.md`（为什么）→ `docs/implementation/elixir/<module>.md`（怎么做）
3. [implementation/elixir/PROGRESS.md](implementation/elixir/PROGRESS.md) — 当前进度与下一项任务
4. [specs-index.md](specs-index.md) — 对应 Phase 的 `.kiro/specs/*/design.md`（开发要点）
5. [AGENTS.md](../AGENTS.md) — TDD、双通道、文档同步等硬约束

### 查 REST / HTTP 接口

→ [implementation/elixir/http-api-reference.md](implementation/elixir/http-api-reference.md)（逐接口参数 + curl）

### 查 WebSocket 协议时序

→ [design/protocol/protocol.md](design/protocol/protocol.md)（规范）  
→ [implementation/elixir/protocol-e2e-message-sequences.md](implementation/elixir/protocol-e2e-message-sequences.md)（E2E 自动生成时序）

### 第三方交付 / 运维

| 文档 | 说明 |
| --- | --- |
| [DELIVERY.md](DELIVERY.md) | **第三方交付手册**（验收、Bootstrap、文档导航） |
| [KNOWN-LIMITATIONS.md](KNOWN-LIMITATIONS.md) | **已知限制清单**（v1 能力边界） |
| [release-deploy-test.md](implementation/elixir/release-deploy-test.md) | Release → K8s → 冒烟 |
| [flamegraph.md](implementation/elixir/flamegraph.md) | **CPU 火焰图**（`mise run flamegraph`） |
| [deploy-guide.md](implementation/elixir/deploy-guide.md) | 生产部署指南 |
| [fault-drill.md](implementation/elixir/fault-drill.md) | 故障演练 |
| [deploy/elixir/](../deploy/elixir/) | K8s 清单与 Dockerfile |
| [overlays/prod/](../deploy/elixir/im/k8s/overlays/prod/) | **生产 K8s 模板** |

### AI / 协作者

1. [AGENTS.md](../AGENTS.md) — **必读**：§文档地图、规模前提、协议为准、Skill 优先
2. [module-map.md](module-map.md) — 改功能前定位文档与代码
3. [design/doc-sync-checklist.md](design/doc-sync-checklist.md) — 协议/文档扇出合入前清单
4. [.agents/skills/im-implementation/SKILL.md](../.agents/skills/im-implementation/SKILL.md) — 开发循环与验证命令
5. [design-decisions.md](design-decisions.md) + [PROGRESS.md](implementation/elixir/PROGRESS.md) — 活状态
6. [specs-index.md](specs-index.md) — `.kiro/specs/` 阶段规格索引

---

## 活索引（状态变更时维护）

| 文档 | 用途 |
| --- | --- |
| [product-overview.md](product-overview.md) | 产品介绍（对外推介首读） |
| [design/architecture-overview.md](design/architecture-overview.md) | **系统架构总览（活文档）** |
| [design-decisions.md](design-decisions.md) | 已确认设计模块（DD-xxx） |
| [implementation/elixir/PROGRESS.md](implementation/elixir/PROGRESS.md) | 实施进度与下一项任务 |
| [module-map.md](module-map.md) | 功能模块对照表 |
| [specs-index.md](specs-index.md) | Kiro 阶段/特性规格索引（`.kiro/specs/`） |

协议规范：[design/protocol/protocol.md](design/protocol/protocol.md) + [proto/](../proto/)

---

## 文档分层

```text
proto/                              # 机器可读协议（权威契约）
docs/
├── README.md                       # 本文件：总入口 + 角色导航
├── module-map.md                   # 功能模块对照表（设计↔实现↔代码）
├── product-overview.md             # 产品介绍
├── design-decisions.md             # 设计决策索引（DD-xxx）
├── design/                         # 设计意图（语言无关）
│   ├── architecture-overview.md    # 架构活文档
│   ├── protocol/protocol.md        # 协议规范
│   └── *.md                        # 各模块设计
└── implementation/
    ├── monorepo-layout.md          # apps/ + deploy/ 仓布局
    ├── elixir/                     # Elixir 实现文档
    └── web/                        # Web 控制台实现
apps/                               # 可运行实现
deploy/                             # 部署清单（见 deploy/README.md）
AGENTS.md                            # AI 协作约定
.kiro/specs/                        # Kiro 阶段/特性规格（见 specs-index.md）
.agents/skills/                     # Agent Skill
```

**不维护**：本文件下的完整文件树（易过期）。模块列表见 [design/README.md](design/README.md) 与 [implementation/elixir/README.md](implementation/elixir/README.md)。

---

## 分类索引

| 分类 | 入口 |
| --- | --- |
| **第三方交付** | [DELIVERY.md](DELIVERY.md) · [KNOWN-LIMITATIONS.md](KNOWN-LIMITATIONS.md) |
| 产品介绍（对外推介） | [product-overview.md](product-overview.md) |
| **功能模块对照（推荐）** | [module-map.md](module-map.md) |
| **Kiro Spec 索引** | [specs-index.md](specs-index.md) |
| 协议规范 | [design/protocol/protocol.md](design/protocol/protocol.md) |
| 数据库 | [design/database/database-design.md](design/database/database-design.md) |
| 系统架构（首读） | [design/architecture-overview.md](design/architecture-overview.md) |
| 系统架构（详细时序） | [design/system-design.md](design/system-design.md) |
| 设计文档全集 | [design/README.md](design/README.md) |
| Elixir 实现 | [implementation/elixir/README.md](implementation/elixir/README.md) |
| HTTP REST 接口 | [implementation/elixir/http-api-reference.md](implementation/elixir/http-api-reference.md) |
| Web 控制台 | [implementation/web/web-console.md](implementation/web/web-console.md) |
| Java（预留） | [implementation/java/README.md](implementation/java/README.md) |
| 应用总览（含文档对照） | [apps/README.md](apps/README.md) |
| 部署 | [deploy/README.md](../deploy/README.md) · [deploy/elixir/](../deploy/elixir/) |
| AI 协作 | [AGENTS.md](../AGENTS.md) |

---

## Proto 文件

| 文件 | 内容 |
| --- | --- |
| [common.proto](../proto/common.proto) | Packet、CmdType、ErrorCode、ChatType |
| [auth.proto](../proto/auth.proto) | 鉴权、心跳、踢人 |
| [message.proto](../proto/message.proto) | 消息体、发送、推送、ACK、已读、撤回、编辑、阅后即焚 |
| [sync.proto](../proto/sync.proto) | 离线拉取 |
| [passthrough.proto](../proto/passthrough.proto) | 透传指令 |
| [group.proto](../proto/group.proto) | 群组管理 |
| [room.proto](../proto/room.proto) | 聊天室管理 |
| [friend.proto](../proto/friend.proto) | 好友管理 |
| [channel.proto](../proto/channel.proto) | 应用通道（App Channel） |
| [event.proto](../proto/event.proto) | Kafka 事件总线（旁路，非 WebSocket 协议） |

校验：`mise run proto-check` · 生成：`mise run proto-gen`

---

## 相关链接

- [根 README](../README.md)
- [deploy 索引](../deploy/README.md)
- [apps 索引](../apps/README.md)
- [设计文档索引](design/README.md)
- [Elixir 实现索引](implementation/elixir/README.md)
- [AI 协作约定](../AGENTS.md)（含 §文档地图）
