# Elixir IM 服务 `lib/` 布局（P0-01 / P0-05）

| 项 | 内容 |
|------|------|
| 状态 | **权威**（`lib/` 细节；仓级布局见 [monorepo-layout.md](../monorepo-layout.md)） |
| 项目路径 | **`apps/elixir/im/`**（非仓库根） |
| 路线图 | P0-01 创建 mix 项目；P0-05 空模块骨架 |
| 架构 | [modular-architecture.md](../../design/modular-architecture.md) §1.3、[dual-channel-api.md](dual-channel-api.md) |
| 协议 | **实现须严格对齐** [`proto/`](../../../proto/) + [`protocol.md`](../../design/protocol/protocol.md)；改协议须人工确认（[`agent.md`](../../../agent.md)） |

> P0-05 验收：在 `apps/elixir/im/` 下目录存在且 `mix compile` 通过；占位模块须有 `@moduledoc` + 公共函数 `@doc`/`@spec`（见 §文档与 ExDoc）。

---

## 文档与 ExDoc

所有 **`lib/im*` 公共 API** 须具备完整文档属性，供 `mix docs` 生成 HTML。**`@moduledoc` / `@doc` 正文使用简体中文**（见 [`agent.md`](../../../agent.md)「中文优先」）。

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
    ├── im/
    │   ├── application.ex
    │   ├── repo.ex
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
    │   ├── domain/
    │   ├── telemetry/
    │   └── log.ex
    └── im_web/
        ├── endpoint.ex
        ├── router.ex
        └── controllers/api/v1/
```

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

- [ ] `mix new im --sup`（P0-01）后 `lib/im/application.ex` 启动 Endpoint、Telemetry
- [ ] `lib/im/protocol/*.ex` 空模块占位
- [ ] `lib/im/application/dispatch.ex` 空 `execute/3` → `{:error, :not_implemented}`（含 `@moduledoc`、`@doc`、`@spec`）
- [ ] `services/`、`delivery/`、`ingress/`、`websocket/commands/` 目录存在
- [ ] `lib/im_web/router.ex` 注册 `GET /health` → 200
- [ ] `test/im_web/health_test.exs` 断言 `/health`

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
