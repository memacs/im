# Release → K8s → Test（与线上一致）

本文档定义 IM 服务端 **唯一认可的集成验收路径**：在本地用与线网 **相同的 Dockerfile 构建 Release 镜像**，部署到 **Kubernetes**，再在集群内/端口转发后做功能测试。

> **原则**：`mix phx.server` / `iex -S mix` 仅用于开发调试；**标 `done` 的功能验收必须在 Release + K8s 环境通过**（P0-10 完成后，自 Phase 2 起强制执行）。

---

## 为什么必须走这条路径

| 仅本地 `mix test` | Release + K8s |
| --- | --- |
| 使用 dev 配置、无 ERTS 打包 | 与生产相同的 `mix release` 产物 |
| 环境变量、路径与容器不一致 | ConfigMap / Secret 注入，与线上一致 |
| 单进程，无法验证多副本 | `kubectl scale` 验证扇出、滚动发布 |
| 易遗漏 `REPLACE_OS_VARS`、SSL 等 | Dockerfile runtime 阶段与线网相同 |

百万在线系统的 bug 常出现在 **Release 与 dev 差异**、**多节点**、**依赖 Service DNS** 上；因此实施路线图将本流程写入 DoD。

---

## 黄金路径（本地 OrbStack）

```text
代码变更
  → mix test（单元/快速反馈）
  → docker build -f deploy/elixir/im/Dockerfile -t im:local .    # 容器内 mix release
  → kubectl apply -k deploy/elixir/im/k8s/overlays/local/      # 依赖 + IM Deployment
  → kubectl rollout status deployment/im
  → 冒烟 / 协议集成测试（port-forward 或集群内 Job）
```

**一键脚本**（推荐）：

```bash
chmod +x deploy/elixir/im/scripts/release-deploy-local.sh
./deploy/elixir/im/scripts/release-deploy-local.sh
```

等价于依次执行：构建镜像 → 部署全栈 → 等待 rollout → 打印状态。

---

## 与线上的一致性

| 维度 | 本地 `overlays/local` | 线上（规划） |
| --- | --- | --- |
| **Dockerfile** | `deploy/elixir/im/Dockerfile` | **同一文件** |
| **构建命令** | `docker build -f deploy/elixir/im/Dockerfile` | CI 相同命令，tag 为版本号 |
| **运行入口** | `bin/im start` | 相同 |
| **基础镜像** | `elixir:1.19.5-otp-28` → `debian:bookworm-slim` | 相同 |
| **配置注入** | ConfigMap + Secret | 相同结构，值来自生产 Secret 管理 |
| **依赖连接** | K8s Service DNS（postgres/redis） | 相同模式 |
| **镜像 tag** | `im:local` | `im:<git-sha>` 或 semver |
| **Overlay** | `deploy/elixir/im/k8s/overlays/local` | 未来 `overlays/prod` 仅 patch 副本数/资源/Secret |

线上 overlay 尚未创建时，**本地 overlay 的 IM Deployment/Service 清单即为线上清单的基础**；生产仅增加副本、HPA、Ingress、外部 Secret，不另写一套 Deployment。

---

## 目录与入口

```text
deploy/elixir/im/
├── Dockerfile                 # Release 多阶段构建（唯一真相）
├── scripts/
│   └── release-deploy-local.sh
└── k8s/
    ├── kustomization.yaml     # 仅依赖（redis + postgres）
    ├── im/                    # IM Release Deployment / Service / ConfigMap
    └── overlays/
        └── local/             # 本地全栈：依赖 + im:local

# 仓库根目录另有 .dockerignore（docker build 上下文用）
```

| 命令 | 用途 |
| --- | --- |
| `kubectl apply -k deploy/elixir/im/k8s/` | 只起依赖 |
| `kubectl apply -k deploy/elixir/im/k8s/overlays/local/` | **依赖 + IM Release（验收用这个）** |
| `./deploy/elixir/im/scripts/release-deploy-local.sh` | 构建 + 部署 + 等待 rollout |

---

## 环境变量与配置

IM Pod 通过 `deploy/elixir/im/k8s/im/configmap.yaml` 与 `secret.yaml` 注入，与 Release 运行时一致：

| 变量 | 来源 | 说明 |
| --- | --- | --- |
| `DATABASE_URL` | ConfigMap | 指向集群内 `postgres` Service |
| `REDIS_URL` | ConfigMap | 指向集群内 `redis` Service |
| `PHX_HOST` | ConfigMap | URL 生成用主机名；`runtime.exs` 以 `fetch_env!` 读取，缺失即启动失败 |
| `PHX_SERVER` | ConfigMap | `true` 时才启动 HTTP 监听 |
| `LOG_LEVEL` | 可选 | 默认 `warning`（见 observability.md §2.6）；排障可临时设 `info` / `debug` |
| `SECRET_KEY_BASE` | Secret | 本地占位；生产走外部 Secret |
| `RELEASE_COOKIE` | Secret | 多节点集群必需（Phase 9） |
| `RELEASE_DISTRIBUTION` / `RELEASE_NODE` | ConfigMap（单副本默认） | 单副本：`name` + `im@127.0.0.1`；多副本每 Pod 唯一节点名，见 [k8s/README.md](../../../deploy/elixir/im/k8s/README.md) §分布式 Erlang |
| `IM_NODE_ROLE` | ConfigMap | `access` / `message`（Phase 9 分角色） |

应用须在 `config/runtime.exs` 读取上述变量（Phase 0 脚手架时配置），**禁止** Release 镜像依赖 dev.exs 本地路径。

---

## 测试分层

| 层级 | 何时跑 | 命令/方式 |
| --- | --- | --- |
| **L1 单元** | 每次改代码 | `mix test` |
| **L2 Release 构建** | 每次合入前 | `docker build -f deploy/elixir/im/Dockerfile -t im:local .` |
| **L3 K8s 部署** | 功能任务验收 | `./deploy/elixir/im/scripts/release-deploy-local.sh` |
| **L4 冒烟** | L3 之后 | `curl http://localhost:4000/health/live` 与 `/health/ready`（port-forward 后） |
| **L5 协议集成** | Phase 2+ | WebSocket 客户端对 `im` Service 发 `CMD_AUTH_REQ` 等 |
| **L6 多副本** | Phase 5+ / 9 | `kubectl scale deployment/im --replicas=2` 后重复 L5 |

**任务 DoD（Phase 2 起）**：L1 + L3 + 该任务对应的 L4/L5 通过，方可标 `done`。

---

## 健康检查

存活与就绪 **分离**（见 `IM.Health`、`IMWeb.HealthController`）：

| 端点 | 探针 | 是否查库 | 失败后果 |
| --- | --- | --- | --- |
| `GET /health/live` | `livenessProbe` / `startupProbe` | 否 | 重启容器 |
| `GET /health/ready` | `readinessProbe` | 是（`SELECT 1`） | 摘除流量，**不**重启 |
| `GET /health` | 冒烟脚本兼容入口 | 否 | — |

存活探针不查库是刻意设计：数据库短暂抖动若触发 liveness 失败，会导致整个集群同时重启，
恰好在数据库最需要降载时雪上加霜。

```bash
kubectl -n im-dev port-forward svc/im 4000:4000
curl -sf http://localhost:4000/health/live    # {"status":"ok"}
curl -sf http://localhost:4000/health/ready   # {"status":"ok","database":"connected"}
```

## 数据库迁移

生产 Release 内没有 Mix，`mix ecto.migrate` 不可用：

```bash
kubectl -n im-dev exec deployment/im -- /app/bin/migrate
# 等价于 bin/im eval "IM.Release.migrate()"
```

脚本来自 `apps/elixir/im/rel/overlays/bin/migrate`，由 Dockerfile 的 `COPY apps/elixir/im/rel rel` 带入 Release。

---

## mise 任务

全部任务定义在仓库根目录 [`mise.toml`](../../mise.toml)。常用：

```bash
mise run check              # proto + compile + test
mise run release-build      # docker build Release 镜像
mise run release-deploy     # 构建 + 部署 K8s
mise run release-deploy-skip-build
mise run k8s-port-forward   # 另开终端
mise run release-smoke      # curl /health
mise run verify             # check + release-deploy
```

`mise tasks` 查看完整列表。

---

## CI（规划）

CI 应与本地黄金路径同构：

1. `mix test`
2. `docker build -f deploy/elixir/im/Dockerfile -t im:$CI_COMMIT_SHA .`
3. （可选）kind / OrbStack CI）`kubectl apply -k deploy/elixir/im/k8s/overlays/local` + 冒烟 Job

---

## 相关文档

- [`deploy/elixir/im/k8s/README.md`](../../deploy/elixir/im/k8s/README.md) — OrbStack 操作细节
- [`deploy/elixir/im/k8s/README.md`](../../deploy/elixir/im/k8s/README.md) — K8s、mise、Dockerfile
- [`project-structure.md`](project-structure.md) — `lib/im/` 布局
- [`roadmap.md`](roadmap.md) — P0-09、P0-10 与各 Phase DoD
- [`.agents/skills/im-implementation/SKILL.md`](../../.agents/skills/im-implementation/SKILL.md) — AI 验收规则
- [`.agents/skills/kubernetes-skill/SKILL.md`](../../.agents/skills/kubernetes-skill/SKILL.md) — K8s 清单审查（上游 [LukasNiessen/kubernetes-skill](https://github.com/LukasNiessen/kubernetes-skill)）
