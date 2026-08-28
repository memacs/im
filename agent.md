# Agent 指南（IM）

本文件供 AI / 协作者快速建立项目上下文。**所有代码以协议为准**（`proto/` + [`protocol.md`](docs/design/protocol/protocol.md)）；改协议须 **人工确认**。写代码前先读本文与对应 design 文档。

## 文档地图

**新会话首轮**：按任务类型选入口，勿从仓库根盲目 grep。

```text
对外 / 产品能力     docs/product-overview.md
        │
总入口（按角色）    docs/README.md
        │
├─ 改某功能        docs/module-map.md  → design/*.md → implementation/elixir/*.md → apps/elixir/im/lib/
├─ 按 Phase 开发    docs/specs-index.md → .kiro/specs/*/design.md → PROGRESS.md → roadmap.md
├─ REST 接口       docs/implementation/elixir/http-api-reference.md
├─ WS 时序         docs/design/protocol/protocol.md + protocol-e2e-message-sequences.md
├─ 启动 / 配置     apps/README.md → apps/<app>/README.md
├─ 部署 / K8s      deploy/README.md → deploy/elixir/im/k8s/README.md
├─ K8s Pod 排障    .agents/skills/im-k8s-debug/SKILL.md（RPC + trace 日志）
├─ CPU 火焰图      docs/implementation/elixir/flamegraph.md → mise run flamegraph
└─ 活状态          design-decisions.md · architecture-overview.md · PROGRESS.md
```

| 你在做… | 先读 |
| --- | --- |
| 任意代码变更 | 本文 → [`module-map`](docs/module-map.md) 定位行 |
| 继续 roadmap / TDD | [`im-implementation`](.agents/skills/im-implementation/SKILL.md) → [`PROGRESS`](docs/implementation/elixir/PROGRESS.md) |
| 协议 / cmd 变更 | [`protocol.md`](docs/design/protocol/protocol.md) + [`doc-sync-checklist`](docs/design/doc-sync-checklist.md)（**须人工确认**） |
| 系统级架构变更 | [`architecture-overview.md`](docs/design/architecture-overview.md) |
| 合入前文档扇出 | [`doc-sync-checklist`](docs/design/doc-sync-checklist.md) §2 + §2.6 grep |

完整索引：[docs/README.md](docs/README.md) · [apps/README.md](apps/README.md) · [deploy/README.md](deploy/README.md)

---

## 项目是什么

自研 IM 系统，传输为 **WebSocket 二进制帧**，序列化为 **Protobuf 3**，当前协议版本 `ver = 1`。

已覆盖能力：登录鉴权、单聊 / 群聊 / 聊天室、ACK、心跳、撤回、编辑、阅后即焚、离线拉取、透传、单条/批量下行、消息投递优先级。

## 规模前提（做任何改动必考虑）

本系统的目标是 **百万级在线**、**高并发消息**、**多节点水平扩展**。

**做任何改动时自检**：
1. 该方案在 **100 万在线、多节点** 下是否仍成立？有无单点或 O(N) 瓶颈？
2. 新增状态放哪？能否水平扩展？
3. 跨节点通信是否必要？
4. 是否与协议 QoS 冲突？
5. 文档 / 注释 / 代码是否同步？
6. **系统级变更是否已更新 [architecture-overview.md](docs/design/architecture-overview.md)？**（模块、数据流、角色、能力边界）
7. 新增/变更 cmd 或主路径时，是否同步 [observability.md](docs/design/observability.md) 埋点？
8. 生产日志是否遵守 **`:warning` 起打、成功路径零日志、§2.6.0 统一 JSON 格式**（经 `IM.Log`，禁止直接 `Logger.*`）？
9. Kafka 旁路是否 **异步、不阻塞主路径**？见 [kafka-event-bus.md](docs/design/kafka-event-bus.md)
10. 热路径是否 **少拷贝**：PUSH/Kafka 透传 `binary`，避免重复 decode/encode？见 [zero-copy-delivery.md](docs/design/zero-copy-delivery.md)
11. 实现是否与 **现有协议** 一致？若需改 `proto`/cmd 语义，是否已获 **人工确认**？

详见：[`docs/design/modular-architecture.md`](docs/design/modular-architecture.md)、[`docs/implementation/elixir/project-structure.md`](docs/implementation/elixir/project-structure.md)、[`agent.md`](agent.md) 规模自检。

## 目录

```text
proto/                 # 协议（语言无关）
docs/                  # 设计 + 实现文档
apps/                  # 可运行实现（elixir/im、elixir/im_client、web/im-console、loadtest；java/im 预留）
deploy/                # 与 apps 对应的部署清单
.agents/skills/        # Agent Skill（上游见 skills/README.md）
```

仓布局：[docs/implementation/monorepo-layout.md](docs/implementation/monorepo-layout.md)。文档活索引：[docs/README.md](docs/README.md)、[module-map.md](docs/module-map.md)、[architecture-overview.md](docs/design/architecture-overview.md)、[design-decisions.md](docs/design-decisions.md)、[PROGRESS.md](docs/implementation/elixir/PROGRESS.md)。

## 硬约束

### 中文优先

**能用简体中文的地方一律用中文**，保持团队文档与代码注释可读一致。

| 使用中文 | 保留英文 |
| --- | --- |
| 设计/实现文档、`agent.md`、`.agents/skills/` 正文 | 代码标识符、模块名、函数名 |
| `@moduledoc` / `@doc` **正文**（ExDoc 生成内容） | `@spec` 类型、协议字段名、`CmdType` 等 |
| 业务语义注释、PR/汇报、错误 `msg` 的人类可读描述 | 行业标准缩写：HTTP、WebSocket、JSON、Kafka、ExUnit 等 |
| 测试用例 `describe` / `test` 名称（描述行为） | 文件路径、mix 命令、环境变量 |

`@doc` 示例：写「发送单聊消息，与 CMD_MSG_SEND 共用」，并附 `## 示例` 调用代码；不要整段英文说明。

### Skill 优先

**进行任何开发、调试、设计（含文档与协议）之前，必须先检查 `.agents/skills/` 是否有适用的 skill，并优先阅读、遵循后再动手。**

| 要求 | 说明 |
| --- | --- |
| **时机** | 会话开始、接新任务、改代码/修 bug、写设计、做评审前 |
| **动作** | 根据任务类型匹配 skill（见下文「Agent Skill」）；**有则必读**，无则按 `agent.md` 与 `docs/` 继续 |
| **范围** | 不限 Elixir：部署、测试、安全、可观测性等均有对应 skill |
| **实施入口** | 服务端实现与开发循环 → [`im-implementation`](.agents/skills/im-implementation/SKILL.md) |
| **禁止** | 跳过 skill 直接写代码/改设计（除非已确认无匹配 skill） |
| **禁止改 skill 文件** | 除非用户**明确要求**修改 skill，**不得**编辑 `.agents/skills/` 下任何文件（含 `SKILL.md`、上游 vendor 内容）；仅阅读、引用；说明性文档写在 `agent.md` / `docs/` |

### 文档一致性

**所有修改必须保证「文档、注释、代码」三者语义一致，禁止只改其一。**

> **历史教训（必读）**：阅后即焚（DD-036）合入时曾出现 **18+ 处文档扇出遗漏**（只改了主设计文档与 proto，未同步 dual-channel、Kafka、roadmap 总览表、实现挂钩等）。**新增/变更协议能力前必须先读并完成** [`docs/design/doc-sync-checklist.md`](docs/design/doc-sync-checklist.md) **§2 勾选 + §2.6 grep 验收**；禁止重复同类错误。

**架构总览同步（硬约束）**：任何 **系统级** 变更（协议能力、模块划分、分层、数据流、部署拓扑、对外能力边界、核心角色关系）在合入前 **必须** 同步更新 [`docs/design/architecture-overview.md`](docs/design/architecture-overview.md)。该文档是面向全团队的 **活架构图**；专题设计（`docs/design/<module>.md`）写「为什么」，总览写「系统长什么样」；**每个功能模块须有 `## 完整流程` 图**。

| 须更新总览 | 可不更新总览 |
| --- | --- |
| 新增/删除能力模块、cmd 分区、双通道范围 | 纯 Elixir 实现细节、单测、内部函数重命名 |
| 改分层（Router/Dispatch/Delivery 职责） | 错别字、不影响语义的注释 |
| 改登录/发消息/推送主路径 | 仅改 `implementation/elixir/*.md` 的代码示例 |
| 改 PG/Redis/Kafka/推送在架构中的角色 | 局部性能优化且对外行为不变 |
| 改单聊/群聊/聊天室能力差异 | |

详见：[`docs/design/protocol/protocol.md`](docs/design/protocol/protocol.md)

### 协议为准（硬约束）

**所有代码开发必须以协议为唯一行为契约**；协议变更 **必须经人工确认** 后方可动手。

| 项 | 约定 |
| --- | --- |
| **权威来源** | [`proto/`](proto/) + [`docs/design/protocol/protocol.md`](docs/design/protocol/protocol.md)。`docs/design/*.md` 解释设计意图，**不得**覆盖协议已定义的字段语义、cmd 时序与错误模型 |
| **适用范围** | **全部**实现代码：`apps/elixir/im`、`apps/elixir/im_client`、`apps/web/im-console`、`apps/elixir/loadtest` 等；REST JSON 字段语义与对应 `proto` message 一致（见 [dual-channel-api.md](docs/design/dual-channel-api.md)） |
| **开发时** | 先读 `proto` + `protocol.md` + 对应 `docs/design/<module>.md`；实现 cmd、payload、状态机、错误码须 **逐条对齐** 协议；测试断言以协议为准，不以「当前代码行为」为准 |
| **禁止** | 为实现方便擅自增删改 cmd/字段、改时序、在代码里发明协议未定义的行为；协议无法满足需求时 **停止编码**，提出变更方案等人审 |
| **协议变更** | 修改 `proto/`、`protocol.md` 或 **已确认** 设计文档中的协议语义前，**必须获得人工确认**；AI **不得**擅自改协议（含「顺手改 proto」、扩大/缩小 cmd 语义） |
| **不一致时** | 代码 ≠ 协议 → **改代码**；协议与设计文档矛盾 → **停下**，列选项请人确认改协议还是改设计 |
| **优先级** | `proto/` + `protocol.md` > `agent.md` > `roadmap.md` > 实现代码 |

协议变更流程见下文「修改协议工作流」；与 [roadmap 人工确认门禁](docs/implementation/elixir/roadmap.md#人工确认门禁) 叠加适用。

### 文档组织结构

**设计文档分为：语言无关（`docs/design/`）+ 语言相关（`docs/implementation/{language}/`）。**

**活索引**（状态变更时维护）：[`design-decisions.md`](docs/design-decisions.md)、[`PROGRESS.md`](docs/implementation/elixir/PROGRESS.md)。`docs/README.md` 与各层 README 仅作入口，不维护完整文件树。

详见：[`docs/design/modular-architecture.md`](docs/design/modular-architecture.md)、[`project-structure.md`](docs/implementation/elixir/project-structure.md)

### 模块化原则

**所有设计必须遵循模块化和服务拆分原则。**

详见：[`docs/design/modular-architecture.md`](docs/design/modular-architecture.md)

核心要点：
- **单一职责**：每个模块只负责一件事
- **关注点分离**：业务逻辑与推送逻辑分离
- **IM Core 只负责投递**：不关心业务逻辑
- **业务层决定推给谁**：IM Core 不参与决策

### 认证模块独立性

**认证模块支持多种认证方式：Token、JWT、OAuth2、自定义。**

详见：[`docs/design/auth-module.md`](docs/design/auth-module.md)

### 依赖抽象原则

**所有外部依赖必须通过抽象层访问，不直接依赖具体实现。**

详见：[`docs/design/dependency-abstraction.md`](docs/design/dependency-abstraction.md)

### 数据库审计时间

**创建写 `created_at`，任意 UPDATE 必须刷新 `updated_at`**；禁止客户端入参覆盖。详见 [`database-design.md`](docs/design/database/database-design.md#审计时间字段created_at--updated_at)。

### 测试驱动开发（TDD）

**实现服务端行为时，必须先写（或更新）测试，再写实现代码。**

| 要求 | 说明 |
| --- | --- |
| **顺序** | 测试先行 → 实现使测试通过 → 必要时重构；禁止先写实现再补「走过场」测试 |
| **范围** | 新功能、bug 修复、协议/行为变更均适用；纯文档、`proto` 语法校验、部署清单等非代码任务除外 |
| **粒度** | 与 roadmap 单项任务对齐：一个任务对应一组可验收的 ExUnit（或集成）用例 |
| **验收** | `mix test` / `mise run ci` 绿后方可标 `PROGRESS` 任务 `done` |
| **DI 优先** | 优先**依赖注入**（Behaviour、`Application.get_env`、显式参数）；测试用内存实现或 `config/test.exs` 切换。**仅**外部边界（不可控 HTTP/第三方 SDK）用 **Mox**；**禁止 ExMachina**，用手写 `test/support` 工厂或 Context 辅助函数造数 |
| **禁止 sleep 同步** | 不得用 `Process.sleep` 等待异步结果；用监听 + `assert_receive`，或 `GenServer.call` 等确定性同步。**例外**：必须真实时间流逝（TTL、退避、超时窗口）可保留 sleep，须**单行注释**说明原因 |

编写测试时遵循 [`.agents/skills/testing-essentials/SKILL.md`](.agents/skills/testing-essentials/SKILL.md)；Phase 2+ 运行时行为另按 [`release-deploy-test.md`](docs/implementation/elixir/release-deploy-test.md) 做 Release + K8s 复测。DI 与 Behaviour 约定见 [`dependency-abstraction.md`](docs/design/dependency-abstraction.md)、[`implementation/elixir/dependency-abstraction.md`](docs/implementation/elixir/dependency-abstraction.md)。

### 测试代码落位（禁止 test-only 进 `lib/`）

**仅用于 ExUnit / E2E / Sandbox / Fake 的模块不得放在 `apps/**/lib/`**（Release、`:peer` 第二 BEAM、压测 worker 均不应依赖「为测试塞进 lib 的代码」）。

| 落位 | 适用 |
| --- | --- |
| `test/support/` | Case 模板、fixtures、集群 E2E 引导（如 `IM.ClusterPeerBoot`）、Mox/Fake |
| `im_client/test/support/` | 客户端断言/场景辅助（`Assertions`、`Scenario`、`FakeTransport`） |
| `lib/` | 生产或 **loadtest 运行时**会加载的代码 |

| 允许留在 `lib/` 的「像测试」代码 | 说明 |
| --- | --- |
| `*.Memory` / `*.Noop` 等 Behaviour 实现 | 由 `config` 切换，生产可启用 |
| 带 `@doc "测试用"` 的 `reset!/snapshot` | 模块本身为生产组件，函数供测试/运维 |

**`:peer` / 跨 BEAM RPC**：须远程调用的测试引导逻辑仍放 `test/support/`；boot 前对 peer 执行 `:code.add_paths(:code.get_path())`，同步主节点 **test 编译路径**，**不要**为此新建 `lib/` 模块。

**path 依赖共享 test 辅助**：模块放在依赖 app's `test/support/`（如 `im_client/test/support/Assertions`）；消费方在 `mix.exs` 的 `elixirc_paths(:test)` 中加入该目录（`im` 已含 `../im_client/test/support`），**仍不得**迁回 `lib/`。

**自检（新增 `lib/` 模块前）**：
1. 非 `test/` 代码是否引用？仅 test 引用 → 迁到 `test/support/`。
2. 是否含 Sandbox、`CLUSTER_E2E`、`protocol_e2e_*`、`ExUnit` 等测试专用逻辑？
3. IM Release / loadtest 是否应打包该模块？

详见 [`project-structure.md`](docs/implementation/elixir/project-structure.md) §测试代码落位。

### 本地 Postgres 端口（OrbStack / mix test）

**跑 `mise run test` 前**：OrbStack 的 Postgres 在 K8s 内，经 `mise run pg-forward` 映射到 **`localhost:15432`**，不是默认的 `5432`。  
未设 `PGPORT` 且未 port-forward 时会出现 `connection refused`，**不等于 DB 未部署**。

| 动作 | 要求 |
| --- | --- |
| 本地验证 | 终端 A：`mise run pg-forward`；终端 B：`mise run test`（mise 自动解析 PGPORT） |
| 裸 `mix test` | 须 `PGPORT=15432`（OrbStack）或 `5432`（GHA / 原生 Postgres） |
| 误判禁止 | 不得在 15432 已通时仍报「DB 不可用」而不试 `PGPORT=15432` |

详见 [`local-dev-gotchas.md`](docs/implementation/elixir/local-dev-gotchas.md)。

### 协议 E2E trace 文档（与用例同步）

[`protocol-e2e-message-sequences.md`](docs/implementation/elixir/protocol-e2e-message-sequences.md) 与 [`protocol-e2e-traces.json`](docs/implementation/elixir/protocol-e2e-traces.json) **由 E2E 测试自动导出**，不得手改后长期偏离用例。

| 动作 | 要求 |
| --- | --- |
| 新增/修改 `test/im_client/protocol/*_test.exs` | 添加 `@tag trace_case: "…"`，关键步骤调用 `trace!/2`（或 `trace_http!/3` / `trace_event!/2`） |
| 更新清单 | 同步 `trace_coverage_test.exs` 的 `@expected_trace_cases` |
| 重新生成文档 | `mise run test` 前确保 pg-forward；或 `PGPORT=15432 mix test.trace` |
| CI / 本地全量 | `trace_coverage_test.exs` 校验 `@tag trace_case` 与 JSON 覆盖一致 |

实现：`IM.ProtocolTraceRegistry` + `IM.ProtocolTraceRender`（`test/support/`），`ExUnit.after_suite` 写 JSON 与 Markdown。

### 双通道一致性（WebSocket + REST）

**凡 IM 已支持的客户端业务能力，须同时提供 WebSocket（`Packet` / `CmdType`）与 REST（`/api/v1`）两种入口，且共用同一套服务层逻辑。**

| 要求 | 说明 |
| --- | --- |
| **单一实现** | WS：`Protocol.Router` → `Commands.*`；REST：`Api.V1.*Controller`；二者仅做适配，业务只写在 `IM.Services.*`，经 `IM.Application.Dispatch` 分发 |
| **契约一致** | REST JSON/Proto 与对应 `proto` message 字段语义一致；错误码与 `ErrorBody` 对齐 |
| **测试** | 同一场景须有 WS + REST 测试，断言行为一致 |
| **例外** | 心跳、服务端下行 PUSH/KICK 等连接态能力可仅 WS；见 [`dual-channel-api.md`](docs/design/dual-channel-api.md) §3 |

### Elixir 文档与类型（ExDoc）

**`apps/elixir/im/` 实现中，所有对外 API 必须具备 `@moduledoc`、`@doc`、`@spec`，以便 `mix docs` 生成可发布文档。**

| 范围 | 要求 |
| --- | --- |
| **公共模块**（`defmodule`） | `@moduledoc` 说明职责、边界、与协议/设计文档的关联 |
| **公共函数**（`def`） | `@doc` + `@spec`；说明参数、返回值、`{:ok,_}` / `{:error,_}` 语义；**含 `## 示例` 代码**（见下） |
| **Behaviour 回调** | `@behaviour` + `@impl` + `@doc`（若 behaviour 未文档化）+ `@spec` |
| **公共类型** | 对外暴露的 struct / 联合类型用 `@type` / `@opaque` 并在 moduledoc 或 types 段说明 |
| **`defp`** | 不强制；复杂私有函数可写 `@spec` private: true（可选） |

| 允许省略 | 说明 |
| --- | --- |
| `@moduledoc false` | **仅**真正内部实现模块（如某 Plug 细节）；须在 PR 中可解释 |
| 测试 `*_test.exs`、`test/support/*` | 不要求 |
| Phoenix 生成样板 | 首次引入后随任务补全文档 |

**`@doc` 最低要求**：**简体中文**一句话摘要 + 必要时 `## 参数` / `## 返回值` / `## 错误`（与 `proto`/cmd 对应关系可保留英文 cmd 名）+ **`## 示例`**（可运行的调用代码，ExDoc 中渲染为代码块）。

**`## 示例` 写法**（公共 `def` 默认要有； trivial getter/setter 可省略并注明理由）：

```elixir
@doc """
发送一条消息。

与 `CMD_MSG_SEND` / `POST /api/v1/messages` 共用。

## 示例

    ctx = %MessageContext{app_key: "demo", user_id: "alice", device_id: "d1", trace_id: "t1"}
    MessageSend.send(ctx, %{chat_type: 1, to: "bob", body: "你好"})

## 返回值

- `{:ok, %{msg_id: ..., conv_seq: ...}}`
- `{:error, :invalid}` — 参数不合法
"""
```

纯函数、无副作用且适合 doctest 时，可用 ExDoc 的 `iex>` 块代替 `## 示例`。

**`@spec` 最低要求**：与实现一致；返回契约统一用 `{:ok, term()} \| {:error, term()}`（或项目内已定义的 `type`）。类型名保持英文。

验收：`mix docs` 可成功生成；新增公共 API 无缺失的 `@doc`/`@spec`（合入前自检）。细则见 [`project-structure.md`](docs/implementation/elixir/project-structure.md) §文档与 ExDoc、[`elixir-essentials`](.agents/skills/elixir-essentials/SKILL.md)。

## 协议核心约定

1. **统一封包**：线上只传 `Packet`
2. **错误模型**：失败一律 `CMD_ERROR` + `ErrorBody`
3. **QoS**：至少一次投递；客户端按 `msg_id` 去重
4. **多端**：发送设备不收自身 PUSH
5. **命令字分区**：1–99 连接；100–199 消息；200–299 ACK；300–399 同步；400–499 撤回/编辑/阅后即焚；500–599 透传；800–822 好友

详见：[`docs/design/protocol/protocol.md`](docs/design/protocol/protocol.md)

## 修改协议工作流

**前置条件（硬约束）**：任何协议语义变更须 **先获人工确认** 再执行下列步骤；未确认前 **禁止** 改 `proto/`、禁止按「新协议」写实现代码。

1. **人工确认**：说明变更动机、影响面（客户端/双通道/存量数据）、是否与已确认 DD 冲突；**待人批准后再继续**
2. 改 `proto/*.proto`
3. 同步更新 `docs/design/protocol/protocol.md`
4. 若该模块已确认：更新/新建 `docs/design/<module>.md`（**含 `## 完整流程` Mermaid 图**）
5. **同步更新 `docs/design/architecture-overview.md`**（系统级变更时；见上文「架构总览同步」）
6. 同步更新 `docs/implementation/elixir/<module>.md`（及 `apps/web/im-console` 等受影响实现文档）
7. **按 [`doc-sync-checklist.md`](docs/design/doc-sync-checklist.md) §2 完成扇出文档 + §2.6 grep 验收**（勿只改主路径）
8. 本地校验：`mise run proto-check`（或 `protoc -I proto --descriptor_set_out=/dev/null proto/*.proto`）
9. **再** 按新协议改实现代码与测试

## Agent Skill

`.agents/skills/` 下每个 skill 一个子目录，入口文件为 `SKILL.md`。**见上文「Skill 优先」硬约束。**

**来源说明**（vendor 拷贝，详见 [`.agents/skills/README.md`](.agents/skills/README.md)）：

| 上游 | 范围 |
| --- | --- |
| **`git@github.com:j-morgan6/elixir-phoenix-guide.git`** | `elixir-essentials`、`ecto-*`、`phoenix-*`、`otp-essentials`、`testing-essentials`、`oban-essentials`、`deployment-gotchas`、`code-quality`、`security-essentials`、`telemetry-essentials` |
| **`git@github.com:redis/agent-skills.git`** | `redis-*`、`iris-development`；IM 业务 Redis 键仍以 [`database-design.md`](docs/design/database/database-design.md) §二、[`permission-cache.md`](docs/design/permission-cache.md) 为准 |
| **`git@github.com:LukasNiessen/kubernetes-skill.git`** | `kubernetes-skill`；IM 部署清单以 [`deploy/`](deploy/) 与 [`release-deploy-test.md`](docs/implementation/elixir/release-deploy-test.md) 为准 |
| **本仓库自研** | `im-implementation`、`design-postgres-tables`、`im-flamegraph`、`im-k8s-debug` |

### 快速匹配

| 你在做… | 优先读 |
| --- | --- |
| **定位某功能的文档与代码** | [`module-map`](docs/module-map.md)（设计↔实现↔代码↔测试） |
| **按 Phase / roadmap 开发** | [`specs-index`](docs/specs-index.md) → `.kiro/specs/` → [`PROGRESS`](docs/implementation/elixir/PROGRESS.md) |
| **新增/变更协议能力、核对文档是否漏改** | [`doc-sync-checklist`](docs/design/doc-sync-checklist.md)（**历史遗漏复盘 + 合入前清单**） |
| 按 roadmap 实现、继续开发、TDD 循环 | [`im-implementation`](.agents/skills/im-implementation/SKILL.md) |
| **写/改任何实现代码（协议为准）** | 先读 `proto/` + [`protocol.md`](docs/design/protocol/protocol.md)；**改协议须人工确认** |
| Web 演示控制台（独立 SPA、协议全覆盖） | [web-console.md](docs/design/web-console.md)、[implementation/web/web-console.md](docs/implementation/web/web-console.md) |
| 写/改 `.ex` 通用风格 | [`elixir-essentials`](.agents/skills/elixir-essentials/SKILL.md) |
| 写/修测试 | [`testing-essentials`](.agents/skills/testing-essentials/SKILL.md) |
| GenServer、Supervisor、进程 | [`otp-essentials`](.agents/skills/otp-essentials/SKILL.md) |
| Ecto schema、查询、迁移 | [`ecto-essentials`](.agents/skills/ecto-essentials/SKILL.md) |
| changeset 多场景校验 | [`ecto-changeset-patterns`](.agents/skills/ecto-changeset-patterns/SKILL.md) |
| 父子表、cast_assoc | [`ecto-nested-associations`](.agents/skills/ecto-nested-associations/SKILL.md) |
| WebSocket / Channel | [`phoenix-channels-essentials`](.agents/skills/phoenix-channels-essentials/SKILL.md) |
| PubSub、跨节点广播 | [`phoenix-pubsub-patterns`](.agents/skills/phoenix-pubsub-patterns/SKILL.md) |
| REST JSON API | [`phoenix-json-api`](.agents/skills/phoenix-json-api/SKILL.md) |
| 鉴权、授权、访问控制 | [`phoenix-auth-customization`](.agents/skills/phoenix-auth-customization/SKILL.md)、[`phoenix-authorization-patterns`](.agents/skills/phoenix-authorization-patterns/SKILL.md) |
| 安全（输入、日志、token） | [`security-essentials`](.agents/skills/security-essentials/SKILL.md) |
| 指标、日志、Telemetry | [`telemetry-essentials`](.agents/skills/telemetry-essentials/SKILL.md) |
| Release、部署配置 | [`deployment-gotchas`](.agents/skills/deployment-gotchas/SKILL.md) |
| **K8s IM Pod 排障、trace、RPC、日志** | [`im-k8s-debug`](.agents/skills/im-k8s-debug/SKILL.md) |
| **CPU 火焰图 / perf 热点** | [`im-flamegraph`](.agents/skills/im-flamegraph/SKILL.md) |
| K8s 清单、Helm、Kustomize、`deploy/` | 上游 [`kubernetes-skill`](.agents/skills/kubernetes-skill/SKILL.md)（见 [skills/README](.agents/skills/README.md)） |
| Oban 后台任务 | [`oban-essentials`](.agents/skills/oban-essentials/SKILL.md) |
| 重构、去重、复杂度 | [`code-quality`](.agents/skills/code-quality/SKILL.md) |
| 文件上传 | [`phoenix-uploads`](.agents/skills/phoenix-uploads/SKILL.md) |
| PostgreSQL 表设计 / 审核 | [`design-postgres-tables`](.agents/skills/design-postgres-tables/SKILL.md) |
| Redis 键空间、数据结构、连接/集群/安全 | 上游 [`redis-core`](.agents/skills/redis-core/SKILL.md) 等（见 [skills/README](.agents/skills/README.md)）；业务键以 `database-design.md` §二 为准 |

未列出的场景：浏览 `.agents/skills/` 目录，按 `SKILL.md` 的 `description` 选择最贴切的一个。

服务端分阶段实施按 [`roadmap.md`](docs/implementation/elixir/roadmap.md) 推进；`im-implementation` 内含任务编排、分层落位与验证命令。

## 本地验收

```bash
mise run check              # 单元测试
mise run ci                 # 提交前完整检查（与 GitHub Actions 对齐）
mise run verify             # check + Release 部署
```

详见：[`docs/implementation/elixir/release-deploy-test.md`](docs/implementation/elixir/release-deploy-test.md)

## 相关链接

- [设计决策索引](docs/design-decisions.md)
- [**文档总索引（按角色导航）**](docs/README.md)
- [**功能模块对照表**](docs/module-map.md)
- [**Kiro Spec 索引**](docs/specs-index.md)（`.kiro/specs/` 阶段规格）
- [**文档同步清单（合入前必跑，勿重复历史遗漏）**](docs/design/doc-sync-checklist.md)
- [**架构总览（活文档，系统变更必维护）**](docs/design/architecture-overview.md)
- [协议规范](docs/design/protocol/protocol.md)
- [数据库设计](docs/design/database/database-design.md)
- [系统设计总览](docs/design/system-design.md)
- [Elixir 实现文档](docs/implementation/elixir/README.md)
- [Agent Skills 索引与上游说明（Elixir/Phoenix、Redis、Kubernetes）](.agents/skills/README.md)
- [可观测性设计](docs/design/observability.md)（指标 + 结构化日志）
- [Kafka 事件总线](docs/design/kafka-event-bus.md)（五 Topic 旁路）
- [离线设备系统推送](docs/design/mobile-push.md)（`im.push` → 推送服务）
- [消息投递少拷贝](docs/design/zero-copy-delivery.md)（热路径 binary 透传）

