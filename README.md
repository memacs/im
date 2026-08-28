# IM

基于 WebSocket + Protobuf 的即时通讯系统。

**当前状态**：协议与设计文档已完成；**Phase 0–13** 核心能力已落地（见 [PROGRESS.md](docs/implementation/elixir/PROGRESS.md)），
Release → K8s 黄金路径、压测与 Web 控制台可运行。
`mise run ci`、`mise run release-deploy`、`mise run release-smoke`、`mise run release-smoke-messaging` 均可使用。

---

## 文档

### 协议设计（语言无关）

| 文档 | 说明 |
|------|------|
| [docs/product-overview.md](docs/product-overview.md) | **产品介绍**（能力、优势、典型场景） |
| [产品介绍（对外推介）](docs/product-overview.md) | **产品能力、场景、对接方式** |
| [docs/README.md](docs/README.md) | **文档总索引**（按角色导航） |
| [docs/module-map.md](docs/module-map.md) | **功能模块对照表**（设计↔实现↔代码） |
| [docs/specs-index.md](docs/specs-index.md) | **Kiro Spec 索引**（`.kiro/specs/`） |
| [docs/design/protocol/protocol.md](docs/design/protocol/protocol.md) | 协议规范 |
| [docs/design/database/database-design.md](docs/design/database/database-design.md) | 数据库设计 |
| [docs/design/architecture-overview.md](docs/design/architecture-overview.md) | **系统架构总览（推荐首读）** |
| [docs/design/system-design.md](docs/design/system-design.md) | 系统架构与时序（详细） |
| [docs/design/](docs/design/) | 设计文档（按模块） |
| [docs/design-decisions.md](docs/design-decisions.md) | 设计决策索引 |

### 实现方案（多语言）

| 语言 | 文档 | 状态 |
|------|------|------|
| **Elixir** | [docs/implementation/elixir/](docs/implementation/elixir/) | Phase 0–13 完成（见 PROGRESS） |
| **Java** | [docs/implementation/java/](docs/implementation/java/) | 预留 |

### 部署配置（多语言）

| 语言 | 文档 | 说明 |
|------|------|------|
| **Elixir** | [deploy/elixir/](deploy/elixir/) | IM + loadtest（见 [deploy/README.md](deploy/README.md)） |
| **Java** | [deploy/java/](deploy/java/) | 预留 |

---

## Proto 文件

| 文件 | 内容 |
|------|------|
| [proto/common.proto](proto/common.proto) | Packet、CmdType、ErrorCode、ChatType |
| [proto/auth.proto](proto/auth.proto) | 鉴权、心跳、踢人 |
| [proto/message.proto](proto/message.proto) | 消息体、发送、推送、ACK、已读、撤回、编辑、阅后即焚 |
| [proto/sync.proto](proto/sync.proto) | 离线拉取 |
| [proto/passthrough.proto](proto/passthrough.proto) | 透传指令 |
| [proto/group.proto](proto/group.proto) | 群组管理 |
| [proto/room.proto](proto/room.proto) | 聊天室管理 |
| [proto/friend.proto](proto/friend.proto) | 好友管理 |
| [proto/channel.proto](proto/channel.proto) | 应用通道（App Channel） |
| [proto/event.proto](proto/event.proto) | Kafka 事件总线（旁路，非 WebSocket 协议） |

---

## 生成代码

需安装 [Protocol Buffers 编译器](https://protobuf.dev/installation/)（`protoc`；`mise install` 已包含）。

**Elixir**（IM 服务端，生成物入库于 `apps/elixir/im/lib/pb/`）：

```bash
mise run proto-plugin      # 首次：装 protoc-gen-elixir
mise run proto-gen         # 生成，改完 .proto 必须重跑
mise run proto-gen-check   # 校验生成物与 proto/ 同步（CI 会跑）
```

其他语言（输出目录需先 `mkdir -p gen/go gen/java`）：

```bash
protoc -I proto --go_out=paths=source_relative:gen/go proto/*.proto
protoc -I proto --java_out=gen/java proto/*.proto

# 仅校验语法
protoc -I proto --descriptor_set_out=/dev/null proto/*.proto
```

---

## 开发环境（mise）

本仓库用 [mise](https://mise.jdx.dev/) 锁定 Erlang/Elixir/protoc 版本，并将常用 `mix` / `kubectl` / `docker` 命令封装为任务。

> **注意**：Mix 项目在 **`apps/elixir/im/`**（根目录无 `mix.exs`）。`mix test` 需要 Postgres，先起本地依赖栈。

```bash
mise install
mise tasks                  # 查看全部任务
mise run k8s-up             # 本地 postgres + redis
mise run pg-forward         # 另开终端常驻：Postgres → localhost:15432（会自动重连）
mise run ci                 # 自动解析 PGPORT（15432 优先）；见 local-dev-gotchas.md
mise run release-deploy     # 构建 Release 镜像并部署到 K8s
```

任务定义见根目录 [`mise.toml`](mise.toml)。

### CI（GitHub Actions）

Push / PR 触发 [`.github/workflows/ci.yml`](.github/workflows/ci.yml)，与本地 `mise run ci` 对齐：

| Job | 条件 | 步骤 |
| --- | --- | --- |
| **Proto** | 始终 | `proto-check` → 装插件 → `proto-gen-check`（生成物防漂移） |
| **Elixir** | 存在 `apps/elixir/im/mix.exs` 时 | `format-check` → `compile --warnings-as-errors` → `hex.audit` → `test`（含 postgres service） |
| **im-console** | 存在 `apps/web/im-console/package.json` 时 | `npm ci` → `vitest` → `vite build` |
| **im_client** | 存在 `im_client/mix.exs` 时 | `mix test` |
| **loadtest** | 存在 `loadtest/mix.exs` 时 | `mix test`（依赖 im_client） |
| **Release 镜像** | 同上 | `docker build -f deploy/elixir/im/Dockerfile` |

本地提交前（mix 项目就绪后）：`mise run ci`。

---

## 本地运行环境（Release + K8s，与线上一致）

集成测试须在 **Release 镜像 + OrbStack Kubernetes** 中执行，不用 dev server 代替验收。

```bash
mise run k8s-up             # 依赖栈（redis + postgres）
mise run release-deploy     # 构建 Release 镜像 + 部署 IM
mise run k8s-port-forward   # 另开终端
mise run release-smoke      # /health/live + /health/ready
mise run im:test-smoke      # 进程内 messaging + auth（CI 同步骤）
```

详见 [docs/implementation/elixir/release-deploy-test.md](docs/implementation/elixir/release-deploy-test.md) 与 [deploy/elixir/im/k8s/README.md](deploy/elixir/im/k8s/README.md)。

---

## 项目结构

```
im/
├── proto/                       # 协议（语言无关）
├── docs/                        # 设计 + 实现文档
├── apps/                        # ★ 可运行实现（各 app 见 apps/README.md）
│   ├── elixir/im/               # 主 IM → apps/elixir/im/README.md
│   ├── elixir/im_client/        # 协议客户端库
│   ├── elixir/loadtest/         # 压测
│   ├── web/im-console/          # Web 演示控制台
│   └── java/im/                 # 预留
├── deploy/elixir/im/            # IM Dockerfile + k8s + scripts
├── mise.toml
└── agent.md                        # AI 协作约定（§文档地图）
```

详见 [monorepo-layout.md](docs/implementation/monorepo-layout.md)、[project-structure.md](docs/implementation/elixir/project-structure.md)。

---

## 技术栈

### 协议层（语言无关）

- **传输**: WebSocket 二进制帧
- **序列化**: Protobuf 3
- **协议版本**: `ver = 1`

### Elixir 实现

已引入：

- **框架**: Phoenix 1.8 + Bandit
- **序列化**: protobuf 0.14（`protoc-gen-elixir` 生成到 `lib/pb/`）
- **持久化**: Ecto SQL + Postgrex (PostgreSQL)
- **跨节点广播**: Phoenix.PubSub

按 Phase 接入：

- **节点发现**: libcluster（Phase 9）
- **连接定位**: Phoenix.Tracker（Phase 5）
- **消息队列**: Broadway (Kafka)（Phase 9）
- **缓存**: Redix (Redis)（Phase 9）

### 部署

- **镜像**: Elixir Release
- **编排**: Kubernetes
- **本地**: OrbStack + kubectl

---

## 快速开始

### 1. 协议校验

```bash
mise run proto-check
```

### 2. Elixir 开发（`apps/elixir/im`）

```bash
mise install
mise run k8s-up             # mix test 需要 postgres
mise run pg-forward         # 另开终端常驻
mise run im:test            # 自动解析 PGPORT，无需手动 export
```

### 3. 本地部署验收

```bash
mise run release-deploy
mise run k8s-port-forward
mise run release-smoke
```

进度与下一项任务见 [PROGRESS.md](docs/implementation/elixir/PROGRESS.md)。

各应用 **启动 / 配置 / 线上部署** 见 [apps/README.md](apps/README.md) 及各子目录 README。

---

## 相关链接

- [部署总览](deploy/README.md)
- [文档总索引](docs/README.md)
- [Elixir 实现文档](docs/implementation/elixir/)
- [Elixir 部署文档](deploy/elixir/)
- [AI 协作约定](agent.md)（含 §文档地图）
