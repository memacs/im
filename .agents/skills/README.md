# Agent Skills

本目录为 Cursor / AI 协作者提供任务级指引。每个 skill 一个子目录，入口文件为 `SKILL.md`。

## 来源分类

| 类别 | 目录 | 上游 |
|------|------|------|
| **Elixir / Phoenix** | `elixir-essentials`、`ecto-*`、`phoenix-*`、`otp-essentials`、`testing-essentials`、`oban-essentials`、`deployment-gotchas`、`code-quality`、`security-essentials`、`telemetry-essentials` | [j-morgan6/elixir-phoenix-guide](https://github.com/j-morgan6/elixir-phoenix-guide) |
| **Redis** | `redis-*`、`iris-development` | [redis/agent-skills](https://github.com/redis/agent-skills) |
| **Kubernetes** | `kubernetes-skill` | [LukasNiessen/kubernetes-skill](https://github.com/LukasNiessen/kubernetes-skill) |
| **IM 自研** | `im-implementation`、`design-postgres-tables`、`im-flamegraph`、`im-k8s-debug` | 本仓库 |

完整索引与任务匹配见 [`agent.md`](../agent.md)「Agent Skill → 快速匹配」。

---

## Elixir / Phoenix Skills（上游）

本项目的 **Elixir、Phoenix、Ecto、测试与部署相关 skill 来自**：

```text
git@github.com:j-morgan6/elixir-phoenix-guide.git
```

HTTPS：`https://github.com/j-morgan6/elixir-phoenix-guide`

当前 vendored 到 `.agents/skills/` 的 skill（与上游 `skills/` 目录一一对应）：

| 目录 | 用途（摘要） |
|------|----------------|
| [`elixir-essentials`](elixir-essentials/SKILL.md) | Elixir 风格、`{:ok,_}` 契约、管道与模式匹配 |
| [`ecto-essentials`](ecto-essentials/SKILL.md) | Schema、查询、迁移 |
| [`ecto-changeset-patterns`](ecto-changeset-patterns/SKILL.md) | 多场景 changeset |
| [`ecto-nested-associations`](ecto-nested-associations/SKILL.md) | 父子表、`cast_assoc` |
| [`otp-essentials`](otp-essentials/SKILL.md) | GenServer、Supervisor |
| [`testing-essentials`](testing-essentials/SKILL.md) | ExUnit、LiveView 测试 |
| [`phoenix-channels-essentials`](phoenix-channels-essentials/SKILL.md) | Channel、WebSocket |
| [`phoenix-pubsub-patterns`](phoenix-pubsub-patterns/SKILL.md) | PubSub 广播 |
| [`phoenix-json-api`](phoenix-json-api/SKILL.md) | REST JSON API |
| [`phoenix-auth-customization`](phoenix-auth-customization/SKILL.md) | phx.gen.auth 扩展 |
| [`phoenix-authorization-patterns`](phoenix-authorization-patterns/SKILL.md) | 授权与策略 |
| [`phoenix-liveview-essentials`](phoenix-liveview-essentials/SKILL.md) | LiveView 生命周期 |
| [`phoenix-liveview-auth`](phoenix-liveview-auth/SKILL.md) | LiveView 鉴权 |
| [`phoenix-uploads`](phoenix-uploads/SKILL.md) | 文件上传 |
| [`oban-essentials`](oban-essentials/SKILL.md) | 后台任务 |
| [`deployment-gotchas`](deployment-gotchas/SKILL.md) | Release、运行时配置 |
| [`code-quality`](code-quality/SKILL.md) | 重构与复杂度 |
| [`security-essentials`](security-essentials/SKILL.md) | 输入、日志、token 安全 |
| [`telemetry-essentials`](telemetry-essentials/SKILL.md) | 指标与 Telemetry |

上游插件名空间为 `elixir-phoenix-guide`（部分 skill 正文会引用 `elixir-phoenix-guide:testing-essentials` 等）。

### 与 IM 项目的关系

| 你在做… | 先读 |
|---------|------|
| 通用 Elixir / Phoenix / Ecto 写法 | 对应上游 skill |
| 按 roadmap 实现、分层落位、TDD 循环 | [`im-implementation`](im-implementation/SKILL.md)（**IM 唯一实施入口**） |
| 协议、cmd、双通道、业务语义 | [`docs/design/`](../docs/design/)、[`agent.md`](../agent.md) |
| PostgreSQL 表结构（IM 业务） | [`design-postgres-tables`](design-postgres-tables/SKILL.md) + [`database-design.md`](../docs/design/database/database-design.md) |

**冲突时**：IM 设计文档与 `agent.md` 硬约束（中文 `@doc`、TDD、双通道等）优先；语言与框架惯例优先采用上游 skill。

**本地化**：`elixir-essentials` 等可能含 IM 专属补丁（如简体中文 `@doc`、链到 `agent.md`）；同步上游后须 diff 并保留这些改动。

### 同步上游

当前为 **vendor 拷贝**（非 git submodule）。更新步骤：

```bash
git clone git@github.com:j-morgan6/elixir-phoenix-guide.git /tmp/elixir-phoenix-guide

# 上游 skills/<name>/ → .agents/skills/<name>/
rsync -av /tmp/elixir-phoenix-guide/skills/elixir-essentials/ .agents/skills/elixir-essentials/
# … 对其余 18 个 skill 重复

# 勿覆盖 IM 自研：im-implementation、design-postgres-tables
```

合入前：恢复 IM 本地化补丁；跑 `mise run ci` 确认无行为回归。

---

## Redis Skills（上游）

本项目的 **Redis 相关 skill 来自**：

```text
git@github.com:redis/agent-skills.git
```

HTTPS：`https://github.com/redis/agent-skills`

| 目录 | 用途（摘要） |
|------|----------------|
| [`redis-core`](redis-core/SKILL.md) | 数据结构选型、键名规范 |
| [`redis-connections`](redis-connections/SKILL.md) | 连接池、管道、超时 |
| [`redis-clustering`](redis-clustering/SKILL.md) | 集群、hash tag、读副本 |
| [`redis-security`](redis-security/SKILL.md) | ACL、TLS、认证加固 |
| [`redis-observability`](redis-observability/SKILL.md) | 指标与可观测命令 |
| [`redis-search`](redis-search/SKILL.md) | RediSearch / 向量检索 |
| [`redis-semantic-cache`](redis-semantic-cache/SKILL.md) | LangCache 语义缓存 |
| [`iris-development`](iris-development/SKILL.md) | Redis Iris Agent Memory |

各 skill 目录下的 `.cursor-plugin/plugin.json` 中 `repository` 字段亦指向同一上游。

### 与 IM 设计文档的关系

Redis skill 讲 **通用 Redis 建模与运维**；IM 业务键空间、TTL、失效策略以设计文档为准：

| 你在做… | 先读 |
|---------|------|
| 缓存键、数据结构、管道/连接 | 对应 `redis-*` skill |
| 收件箱位点、序列号、权限热缓存、应用配置缓存 | [`database-design.md`](../docs/design/database/database-design.md) §二 |
| 拉黑/禁言/封禁 Redis 热路径 | [`permission-cache.md`](../docs/design/permission-cache.md) |
| Elixir `Redix` / `IM.Cache` 实现 | [`database.md`](../docs/implementation/elixir/database.md) §6 |

**冲突时**：IM 设计文档（键名、语义、TTL）优先。

### 同步上游

```bash
git clone git@github.com:redis/agent-skills.git /tmp/redis-agent-skills

rsync -av --delete /tmp/redis-agent-skills/skills/redis-core/ .agents/skills/redis-core/
# … 对其余 redis-* / iris-development 重复
```

---

## Kubernetes Skill（上游）

本项目的 **Kubernetes 清单 / Helm / Kustomize 相关 skill 来自**：

```text
git@github.com:LukasNiessen/kubernetes-skill.git
```

HTTPS：`https://github.com/LukasNiessen/kubernetes-skill`

| 目录 | 用途（摘要） |
|------|----------------|
| [`kubernetes-skill`](kubernetes-skill/SKILL.md) | Manifest 审查、故障模式（资源、网络、权限、滚动发布）、Helm/Kustomize、EKS/GKE/AKS 等 |

上游仓库根目录即 skill 内容；本仓库 vendor 于 `.agents/skills/kubernetes-skill/`。

### 与 IM 项目的关系

| 你在做… | 先读 |
|---------|------|
| K8s YAML、Helm、Kustomize、`deploy/elixir/im/k8s/` | [`kubernetes-skill`](kubernetes-skill/SKILL.md) |
| Elixir Release、运行时配置、`PHX_HOST` | [`deployment-gotchas`](deployment-gotchas/SKILL.md)（elixir-phoenix-guide） |
| 本地 K8s 冒烟、Release 验证流程 | [`release-deploy-test.md`](../docs/implementation/elixir/release-deploy-test.md) |

**冲突时**：IM 仓库内 `deploy/` 目录与 `release-deploy-test.md` 约定优先；通用 K8s 最佳实践采用上游 skill。

### 同步上游

```bash
git clone git@github.com:LukasNiessen/kubernetes-skill.git /tmp/kubernetes-skill

rsync -av --delete \
  --exclude '.git' \
  /tmp/kubernetes-skill/ .agents/skills/kubernetes-skill/
```

合入前 diff，确认未误删 IM 自研 skill。

---

## IM 自研 Skills

| 目录 | 说明 |
|------|------|
| [`im-implementation`](im-implementation/SKILL.md) | 分阶段实施、TDD、PROGRESS、分层落位 |
| [`design-postgres-tables`](design-postgres-tables/SKILL.md) | PostgreSQL 表设计审核 checklist |
| [`im-flamegraph`](im-flamegraph/SKILL.md) | Erlang perf CPU 火焰图（`mise run flamegraph`） |
| [`im-k8s-debug`](im-k8s-debug/SKILL.md) | K8s Pod 内 RPC + 结构化日志 trace 排障 |

由本仓库维护，不随上游 Elixir / Redis skill 同步覆盖。
