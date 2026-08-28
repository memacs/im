# Elixir IM 服务 `lib/` 布局（P0-01 / P0-05）

| 项 | 内容 |
|------|------|
| 状态 | **权威**（`lib/` 细节；仓级布局见 [monorepo-layout.md](../monorepo-layout.md)） |
| 项目路径 | **`apps/elixir/im/`**（非仓库根） |
| 路线图 | P0-01 创建 mix 项目；P0-05 空模块骨架 |
| 架构 | [modular-architecture.md](../../design/modular-architecture.md) §1.3、[dual-channel-api.md](dual-channel-api.md) |
| 协议 | **实现须严格对齐** [`proto/`](../../../proto/) + [`protocol.md`](../../design/protocol/protocol.md)；改协议须人工确认（[`AGENTS.md`](../../../AGENTS.md)） |

> P0-05 验收：在 `apps/elixir/im/` 下目录存在且 `mix compile` 通过；占位模块须有 `@moduledoc` + 公共函数 `@doc`/`@spec`（见 §文档与 ExDoc）。

---

## 文档与 ExDoc

所有 **`lib/im*` 公共 API** 须具备完整文档属性，供 `mix docs` 生成 HTML。**`@moduledoc` / `@doc` 正文使用简体中文**（见 [`AGENTS.md`](../../../AGENTS.md)「中文优先」）。

| 层级 | 模块示例 | 文档要求 |
|------|----------|----------|
| 服务层 | `IM.Services.*` | `@moduledoc` + 每个公共 `def` 的 `@doc`（含 `## 示例`）、`@spec`；链接 `docs/design/*.md` |
| 协议层 | `IM.Protocol.*` | 同上；注明对应 `proto` / 命令字 |
| 存储 Behaviour | `IM.Stores.*` | `@callback` 带 `@doc`（含示例）、`@spec`；实现模块 `@impl` |
| 分发 / 接入 | `IM.Application.Dispatch` | 公共 `execute/3` 等必须文档化 |
| Web 层 | `IMWeb.*Controller` | 公共 action：`@doc` + `@spec(Plug.Conn.t(), ...) :: Plug.Conn.t()` |
| 内部细节 | 某 Plug 子模块 | 允许 `@moduledoc false`；**对外 `def` 仍要中文 `@doc` + `@spec`** |

**不合入**：新增公共 `def` 无 `@doc` 或 `@spec`；`@doc` 无 `## 示例`（无正当理由时）；`@spec` 与实现返回值不一致。

```bash
cd apps/elixir/im && mix docs    # 合入前确认可生成
```

P0-01 创建项目时在 `mix.exs` 加入 `{:ex_doc, "~> 0.37", only: :dev, runtime: false}`（版本随生态调整）。

---

## `apps/elixir/im/lib/` 布局

```text
apps/elixir/im/
├── mix.exs
├── config/
├── test/
├── priv/
└── lib/
    ├── pb/                           # protoc 生成物，勿手改（见下）
    ├── im/
    │   ├── application.ex
    │   ├── repo.ex
    │   ├── health.ex
    │   ├── release.ex
    │   ├── protocol/                 # 协议层（无业务）
    │   │   ├── codec.ex
    │   │   ├── router.ex
    │   │   ├── reply.ex
    │   │   ├── push.ex
    │   │   └── cmd.ex
    │   ├── application/              # 应用分发
    │   │   └── dispatch.ex
    │   ├── ingress/                  # REST 适配（薄）
    │   │   └── http.ex
    │   ├── websocket/
    │   │   ├── connection_state.ex
    │   │   └── commands/             # 一 cmd 一模块 → Dispatch
    │   ├── services/                 # IM.Services.*
    │   ├── delivery/                 # IM.Delivery.Router 等
    │   ├── stores/
    │   ├── cluster/
    │   ├── event_bus/
    │   ├── domain/                   # MessageContext、Error 等跨层值对象
    │   ├── telemetry/
    │   └── log.ex
    └── im_web/
        ├── endpoint.ex
        ├── router.ex
        ├── controllers/
        └── controllers/api/v1/
```

### `lib/pb/`：protobuf 生成代码

| 项 | 约定 |
|------|------|
| 生成命令 | `mise run proto-gen`（首次需 `mise run proto-plugin` 装 `protoc-gen-elixir`） |
| 模块前缀 | `Pb.`（`--elixir_opt=package_prefix=pb`）→ `Pb.Im.Protocol.Packet`、`Pb.Im.Event.*` |
| 目录 | 按模块命名空间分层：`lib/pb/im/protocol/common.pb.ex`、`lib/pb/im/event/event.pb.ex` |
| 版本 | `protoc-gen-elixir` 与 `mix.exs` 的 `:protobuf` **必须同版本**（当前 0.17.0），否则生成物可能调用运行时库没有的 API |
| 是否入库 | **入库**。Docker 构建阶段因此不需要 protoc；代价是改完 `.proto` 必须重跑生成 |
| 防漂移 | CI 跑 `mise run proto-gen-check`，生成物与 `proto/` 不一致即失败 |

前缀不用 `IM.` 是为了和手写的 `IM.Protocol.*` 区分：Elixir 里 `Im` 与 `IM` 是两个模块，
混在同一命名空间下极易看错，且在大小写不敏感的文件系统上同名模块会撞 `.beam` 文件。
`lib/pb/` 全是生成物、`lib/im/` 全是手写代码，边界一眼可辨。

---

## 请求路径（与目录对应）

| 路径 | 目录 |
|------|------|
| WS 入站 | `im_web` Socket → `protocol/*` → `websocket/commands/*` → `application/dispatch` → `services/*` |
| REST 入站 | `im_web/controllers/api/v1/*` → `ingress/http` → `application/dispatch` → `services/*` |
| 下行扇出 | `services/*` → `delivery/router` → WS push / `mobile_push` |

---

## P0-05 最小骨架清单

在 **`apps/elixir/im/`** 下：

- [x] `lib/im/application.ex` 启动 `IM.Repo`、`Phoenix.PubSub`、`IMWeb.Endpoint`（P0-01）；完整监督树见 [application-startup.md](application-startup.md)
- [x] `lib/im_web/router.ex` 注册 `GET /health/live`、`/health/ready`、`/health`（见下）
- [x] `test/im_web/controllers/health_controller_test.exs` 覆盖成功与 503 路径
- [x] `lib/im/protocol/*.ex` 占位（`codec`、`router`、`reply`、`push`、`cmd`）
- [x] `lib/im/domain/{message_context,error}.ex`：`MessageContext` 按 [message-context.md](message-context.md) 定型，`Error` 为跨层统一错误值
- [x] `lib/im/application/dispatch.ex` 空 `execute/3`（含 `@moduledoc`、`@doc`、`@spec`）
- [x] `services/`、`delivery/`、`ingress/`、`websocket/commands/`、`stores/`、`cluster/`、`event_bus/`、`telemetry/` 目录存在
- [x] `test/im/skeleton_test.exs` 锁定骨架契约

**占位返回值**：统一 `{:error, IM.Domain.Error.not_implemented(cmd)}`，而非裸 `{:error, :not_implemented}`。
`@spec` 因此从骨架期就是最终形态 `{:error, IM.Domain.Error.t()}`，Phase 1+ 填实现时不必回头改签名和调用方。

**健康检查为何拆两个端点**：`/health/live` 不查库，失败会重启容器；`/health/ready`
查主库，失败只摘流量。合成一个端点时，浅检查会掩盖故障，深检查会在数据库抖动时
把整个集群一起重启。`/health` 保留为等同 liveness 的兼容入口（`mise run release-smoke`）。
实现见 `IM.Health` 与 `IMWeb.HealthController`，语义见
[`release-deploy-test.md`](release-deploy-test.md) §健康检查。

---

## 测试代码落位

与 [`AGENTS.md`](../../../AGENTS.md)「测试代码落位」一致：

- **`lib/`**：Release / loadtest 运行时会加载的模块。
- **`test/support/`**：ExUnit Case、fixtures、集群 E2E（`IM.ClusterPeerBoot` 等）、Fake/Mox。
- **`im_client/test/support/`**：`IM.Client.Assertions`、`Scenario`、`FakeTransport` 等客户端测试辅助。

`:peer` 第二 BEAM 通过 `:code.add_paths/1` 同步 test 编译路径，**不得**把测试引导模块放进 `lib/`。

`im` 协议 E2E 使用 `im_client/test/support/` 中的断言辅助时，在 `apps/elixir/im/mix.exs` 的 `elixirc_paths(:test)` 加入 `../im_client/test/support`（与 [`AGENTS.md`](../../../AGENTS.md) 一致）。

---

## 相关应用（同仓，不同 Mix 项目）

| 路径 | 说明 |
|------|------|
| `apps/elixir/loadtest/` | 压测服务（Phase 10） |
| `apps/elixir/im_client/` | 可选共享 Codec/WS 客户端 |
| `apps/java/im/` | Java IM（预留） |

见 [monorepo-layout.md](../monorepo-layout.md)。

---

## 相关文档

| 文档 | 用途 |
|------|------|
| [monorepo-layout.md](../monorepo-layout.md) | 单仓 `apps/` + `deploy/` 布局 |
| [roadmap.md](roadmap.md) P0-01、P0-05 | 任务验收 |
| [dual-channel-api.md](dual-channel-api.md) | Dispatch / Ingress |
| [deploy/elixir/im/Dockerfile](../../../deploy/elixir/im/Dockerfile) | Release 构建（context = 仓库根） |
