---
name: im-implementation
description: >-
  IM 服务端分阶段实施与 Elixir 开发循环：选任务、测试驱动开发、分层落位、mise 验证、PROGRESS 更新。
  用户说「继续开发」「按 roadmap 实现」「做下一项」「开始实现」「开发循环」「TDD」或编写 apps/elixir/im 代码时使用。
auto_suggest: true
---

# IM 服务端实施技能

本技能是 **唯一入口**：任务编排（做什么）+ Elixir 开发循环（怎么写）。  
**文档地图**（全项目）：[`AGENTS.md` §文档地图](../../AGENTS.md#文档地图) · [`docs/README.md`](../../docs/README.md) · [`module-map.md`](../../docs/module-map.md)  
语言与框架惯例按需阅读 `elixir-essentials`、`testing-essentials`、`otp-essentials` 等。

**语言**：向用户汇报、文档与代码 `@doc` 正文使用 **简体中文**（见 [`AGENTS.md`](../../AGENTS.md)「中文优先」）。

---

## 触发条件

- 用户要求「继续开发」「按 roadmap」「做下一项」「自动实现到完成」
- 用户要求「开始实现」「写 Elixir」「开发循环」「TDD」
- 任务涉及 `apps/elixir/im/`、`mix.exs`、WebSocket、Packet、消息主路径
- 需要判断「当前该做什么、做到哪算完」

---

## 权威来源（按优先级）

1. [`proto/`](../../proto/) + [`docs/design/protocol/protocol.md`](../../docs/design/protocol/protocol.md) — **做什么**
2. [`AGENTS.md`](../../AGENTS.md) — 硬约束、规模前提、一致性
3. [`docs/implementation/elixir/roadmap.md`](../../docs/implementation/elixir/roadmap.md) — 阶段与验收
4. [`docs/implementation/elixir/PROGRESS.md`](../../docs/implementation/elixir/PROGRESS.md) — **当前做到哪**
5. [`docs/specs-index.md`](../../docs/specs-index.md) — Kiro 阶段/特性 spec（`.kiro/specs/`）
6. [`docs/design/`](../../docs/design/) — 为什么（已确认模块）
7. [`docs/implementation/monorepo-layout.md`](../../docs/implementation/monorepo-layout.md) — `apps/` + `deploy/` 布局
8. [`docs/implementation/elixir/<module>.md`](../../docs/implementation/elixir/) — 怎么做（按模块）
9. 其他 `.agents/skills/*` — 语言/框架惯例

**冲突处理**：协议 > AGENTS.md > roadmap。发现不一致时先对齐文档与 proto，再写代码。

---

## 每轮工作流（总览）

```text
① 读任务上下文 → ② 选定唯一任务 ID → ③ 分层落位
→ ④ 测试驱动（红→绿→重构）→ ⑤ 验证（L0–L4）→ ⑥ 更新 PROGRESS → ⑦ 汇报
```

进度清单：

```text
- [ ] ① 已读 roadmap 验收、proto、implementation/elixir/<module>.md
- [ ] ①b 本阶段/特性已有或已写 Kiro spec（见下）
- [ ] ② PROGRESS 标为 in_progress，未跨阶段
- [ ] ③ 落位与接口已确定（见「分层落位」）
- [ ] ④ 测试先写且先失败（红）→ 最小实现（绿）→ 重构仍绿
- [ ] ⑤ 已跑验证命令（见「验证层级」）
- [ ] ⑥ PROGRESS / 设计文档 / `.kiro/specs/.../tasks.md` 已同步
- [ ] ⑦ 已向用户汇报（简体中文）
```

### Kiro 格式 Spec（实现时必留）

每个 Phase（或独立特性）在动手写代码前，于仓库根维护：

```text
.kiro/specs/<feature-or-phase-id>/
  requirements.md   # 用户故事 + EARS（WHEN…THE SYSTEM SHALL…）
  design.md         # 组件、API、序列图、测试策略
  tasks.md          # 可勾选任务清单（与 roadmap ID 对齐）
```

- 实现过程中更新 `tasks.md` 勾选状态。
- Spec **不替代** `proto` / `protocol.md`；冲突时以协议为准。
- 全量 spec 目录索引：[specs-index.md](../../../docs/specs-index.md)。
- 示例：[phase-1-protocol-adapter](../../../.kiro/specs/phase-1-protocol-adapter/)。

---

## ① 读任务上下文

```
AGENTS.md
  → PROGRESS.md（第一个 pending 且依赖已满足的 ID）
  → roadmap.md 对应阶段验收标准
  → proto + design/<module>.md + implementation/elixir/<module>.md
  → project-structure.md（目录落位）
  → 按需读下方「技术技能路由」
```

**不要**在未读验收标准前写代码。纯文档/proto/部署任务可跳过测试驱动，直接验证。

---

## ② 选定唯一任务

- **一次只做一个任务 ID**（如 `P1-01`）；同一会话内可在验收通过后**自动开始下一任务/下一 Phase**，无需用户逐次回复「继续」（用户若要求连续推进）。
- 仍遵守：不并行混乱跨 Phase；每 Phase 先写/更新 Kiro spec。
- PROGRESS 标为 `in_progress`。
- 触及 roadmap「人工确认门禁」或需改 proto → **停下询问用户**。

---

## ③ 分层落位（写第一行代码前）

### 决策树

```text
协议编解码 / Packet 路由？     → lib/im/protocol/*（无业务、无 DB）
WS 命令入口？                  → lib/im/websocket/commands/*（薄：解码 → Dispatch）
REST 入口？                    → lib/im_web/controllers/api/v1/* + lib/im/ingress/http.ex
业务规则？                     → lib/im/services/*（唯一业务真相）
持久化？                       → lib/im/stores/*（Behaviour + 实现）
下行推送 / 扇出？              → lib/im/delivery/*
跨命令分发？                   → lib/im/application/dispatch.ex
```

### 硬规则

| 规则 | 说明 |
|------|------|
| 业务只写服务层 | 处理器/控制器禁止直接 `Repo` 或 Redis |
| 双通道共用服务 | WS 与 REST 经同一 `Dispatch.execute/3` |
| 外部依赖走 Behaviour | 见 [dependency-abstraction.md](../../docs/design/dependency-abstraction.md) |
| Stores 返回 `{:ok,_}` / `{:error,_}` | 见 `elixir-essentials` |
| 协议层无 IO | Codec/Router 不碰 DB/Redis |

目录详情：[`project-structure.md`](../../docs/implementation/elixir/project-structure.md)。  
测试与代码示例：[`reference.md`](reference.md)。

---

## ④ 测试驱动微循环

遵循 [`AGENTS.md`](../../AGENTS.md)：**先写（或更新）测试，再写实现**；业务能力 WS + REST 双入口经 `Dispatch`。

### 红 → 绿 → 重构

```bash
# 1. 只跑本任务测试（红）
mise run im:compile
cd apps/elixir/im && mix test test/im/services/message_send_test.exs

# 2. 最小实现（绿）→ 再跑同一文件
# 3. 全量防回归
mise run test
```

### 测试放置

| 被测模块 | 测试路径 | 用例基类 |
|----------|----------|----------|
| `IM.Services.*` | `test/im/services/*_test.exs` | `IM.DataCase` |
| `IM.Protocol.*` | `test/im/protocol/*_test.exs` | `ExUnit.Case` |
| `IM.WebSocket.*` | `test/im/websocket/*_test.exs` | WS 用例 / `DataCase` |
| `IMWeb.*` | `test/im_web/controllers/**/*_test.exs` | `IMWeb.ConnCase` |
| 双通道 | 同场景 WS + REST 各一用例 | 断言服务层结果一致 |

- 遵循 [`testing-essentials`](../testing-essentials/SKILL.md)
- 测试夹具放 `test/support/fixtures/`
- `describe` / `test` 名称用 **简体中文** 描述行为
- 成功路径与错误路径都要测

### 实现约束

- **最小 diff**：只改任务相关文件
- **规模前提**：百万在线、多节点；见 `AGENTS.md` 自检
- **协议**：WebSocket 二进制 `Packet`；不用 Channel 字符串传业务
- **主路径**：`CMD_MSG_SEND` 同步 `ACK_DOWN(SERVER_RECEIVED)`，不得异步挂起
- **存储**：存 `ChatMessage` 等业务体，不存 `Packet`
- **文档与类型**：公共 API 须 `@moduledoc`、`@doc`（**中文正文** + **`## 示例`**）、`@spec`（见 `AGENTS.md`）
- **日志**：业务代码 **仅** `IM.Log.*`（**宏 API**，自动带 `caller_module`/`caller_line`）；遵守 [observability.md](../../docs/design/observability.md) §2.6.0 统一 JSON 格式
- 绿灯后重构；**不顺手做下一任务 ID**

### 常见模式

```elixir
# Dispatch：WS/REST 共用
def execute(:msg_send, conn_or_socket, params) do
  IM.Services.MessageSend.send(conn_or_socket, params)
end
```

WS 命令处理器：解 Packet → `Dispatch` → `Reply`/`Push`。  
控制器：解析 JSON → `Dispatch` → 渲染 JSON。  
单元测试用内存 Store / Mox，不依赖真实 Redis/Kafka。

---

## ⑤ 验证层级

| 层级 | 命令 | 何时必做 |
|------|------|----------|
| **L0** | `mise run proto-check` | 改 proto 或生成代码 |
| **L1** | `mise run test`（需 `pg-forward` 或本机 5432） | **每次**代码变更 |
| **L2** | `mise run check` | 准备标 done |
| **L3** | `mise run ci`（format + credo + 全量 test） | 提交前 |
| **L4** | `mise run release-deploy` + `release-smoke` | **阶段 2+** 功能 |

本地依赖：`mise run k8s-up` + `mise run pg-forward`（OrbStack Postgres → `localhost:15432`）。  
`mise run test` **自动解析 `PGPORT`**（15432 优先，其次 5432）；勿在未 port-forward 时误判「DB 不可用」。见 [`local-dev-gotchas.md`](../../docs/implementation/elixir/local-dev-gotchas.md)。

改 proto/行为时同步文档；**系统级变更须更新** [`architecture-overview.md`](../../docs/design/architecture-overview.md)。

---

## ⑥ 更新 PROGRESS

- 验收通过 → 标 `done`，更新阶段分数
- roadmap 不合理 → 备注建议，**不静默偏离**

---

## ⑦ 汇报

**一律简体中文**：

1. 任务 ID + 改了哪些文件（按层列出）
2. 测试：红→绿，相关测试文件
3. 验证：L0–L4 命令与结果
4. 下一项建议任务 ID
5. 是否有人工确认门禁待决

---

## 完成定义

- [ ] 行为符合 `protocol.md` 与 `proto`
- [ ] 符合 `AGENTS.md` 架构约束与 [`project-structure.md`](../../docs/implementation/elixir/project-structure.md)
- [ ] 测试先于实现，描述验收场景
- [ ] 新增/变更公共 API：`@moduledoc`、`@doc`（中文 + `## 示例`）、`@spec`；`mix docs` 可生成
- [ ] `mix compile` / `mix test` / `protoc` 通过；合入前 `mise run ci` + `im:credo` 全绿
- [ ] 阶段 2+：`release-deploy` + K8s 冒烟通过
- [ ] 文档、注释、代码语义一致；系统级变更已更新 `architecture-overview.md`
- [ ] `PROGRESS.md` 已更新
- [ ] 未自动 `git commit`；若用户要求提交，已展示变更与 message 并 **经确认** 后提交（见 [`im-commit-gates`](../im-commit-gates/SKILL.md) §Git 提交规范）

---

## 禁止事项

| 禁止 | 原因 |
| --- | --- |
| 一次实现多个阶段 | 无法验收、易偏离协议 |
| 跳过测试标 done | 破坏可信度 |
| 公共 `def` 无 `@doc` / `@spec` / `## 示例` | 文档不完整，契约不可查 |
| `@doc` 正文用英文（无正当理由） | 违反中文优先 |
| 先实现再补走过场测试 | 违反测试驱动 |
| 阶段 2+ 仅用 mix phx.server 验收 | 与 Release 不一致 |
| 鉴权失败不关连接 | 违反 protocol §5 |
| `CMD_MSG_SEND` 异步等 Hook/Kafka 再 ACK | 违反主路径时序 |
| 聊天室历史塞进 OFFLINE_PULL | 违反协议 |
| 单节点全局 GenServer 扇出百万连接 | 违反规模前提 |
| 未确认改 proto 字段语义 | 须协议评审 |
| 系统级变更未更新 architecture-overview | 架构脱节 |
| 写入密钥、生产配置 | 安全 |

---

## 何时停下问用户

| 情况 | 动作 |
|------|------|
| roadmap 人工确认门禁 | 停止，列选项 |
| proto 字段语义要改 | 停止，先对齐设计 |
| 验收标准与文档冲突 | 停止，报告冲突 |
| 需要新 hex 依赖 | 说明理由，等确认 |
| 任务需拆 PR | 建议拆分，等确认 |

---

## 技术技能路由

### 按阶段

| 阶段 | 建议阅读 |
| --- | --- |
| 0–1 | `elixir-essentials`、`code-quality`；`deploy/elixir/im/k8s/README.md` |
| 2 | `phoenix-channels-essentials`（Socket 参考）、`otp-essentials` |
| 3–4 | `ecto-essentials`、`ecto-changeset-patterns`、`testing-essentials` |
| 5–6 | `phoenix-pubsub-patterns`、`otp-essentials` |
| 7–8 | `phoenix-json-api`、`security-essentials` |
| 9 | `deployment-gotchas`、`telemetry-essentials`、`oban-essentials` |
| 10 | `deployment-gotchas`、`testing-essentials` |

### 按代码类型（按需，勿全读）

| 你在写… | 阅读 |
|---------|------|
| `.ex` 风格、`with`/元组 | `elixir-essentials` |
| ExUnit、测试夹具 | `testing-essentials` |
| GenServer、Supervisor | `otp-essentials` |
| Ecto、迁移 | `ecto-essentials` |
| changeset 多场景 | `ecto-changeset-patterns` |
| Phoenix Socket | `phoenix-channels-essentials` |
| PubSub、跨节点 | `phoenix-pubsub-patterns` |
| REST `/api/v1` | `phoenix-json-api` |
| 鉴权、安全 | `security-essentials` |
| 指标与日志 | `telemetry-essentials` |
| Release 部署 | `deployment-gotchas` |
| Oban 后台任务 | `oban-essentials` |

---

## 自主循环提示词（自动化 / 手动）

```text
按 .agents/skills/im-implementation/SKILL.md 执行：
1. 读 PROGRESS.md，做下一个 pending 任务
2. 分层落位 → 写失败测试 → 最小实现 → 重构
3. mise run test（阶段 2+ 另跑 release-deploy）
4. 更新 PROGRESS，用简体中文汇报
不要 git commit，不要跨阶段。
```

---

## 相关文件

| 文件 | 作用 |
| --- | --- |
| [`roadmap.md`](../../docs/implementation/elixir/roadmap.md) | 阶段任务与验收 |
| [`PROGRESS.md`](../../docs/implementation/elixir/PROGRESS.md) | 状态看板 |
| [`project-structure.md`](../../docs/implementation/elixir/project-structure.md) | `lib/` 布局 |
| [`reference.md`](reference.md) | 测试骨架与代码示例 |
| [`release-deploy-test.md`](../../docs/implementation/elixir/release-deploy-test.md) | Release 与 K8s |
| [`AGENTS.md`](../../AGENTS.md) | 全局约束 |
