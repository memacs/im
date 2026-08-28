# IM 部署指南（Phase 10 / P10-03）

| 项 | 内容 |
| --- | --- |
| 状态 | 已交付骨架 |
| 相关 | [`release-deploy-test.md`](release-deploy-test.md)、`deploy/elixir/im/`、`deploy/elixir/loadtest/` |

---

## 1. 产物

| 产物 | 路径 | 说明 |
| --- | --- | --- |
| IM Release 镜像 | `deploy/elixir/im/Dockerfile` | 生产主服务 |
| 本地 K8s overlay | `deploy/elixir/im/k8s/overlays/local/` | OrbStack / 本地集群 |
| 多副本 overlay | `deploy/elixir/im/k8s/overlays/cluster/` | libcluster + headless + PDB |
| **生产 overlay 模板** | `deploy/elixir/im/k8s/overlays/prod/` | 外部 PG/Redis + Ingress TLS（见 [DELIVERY.md](../../DELIVERY.md)） |
| 压测镜像 / Job | `deploy/elixir/loadtest/` | 独立 Deployment，对 `svc/im` 施压 |

---

## 2. 本地一键（OrbStack / Docker Desktop）

前置：`mise`、Docker、`kubectl` 指向本机集群；Postgres 端口转发见 `mise run pg-forward`。

```bash
# 1) 测试（终端 A 先 mise run pg-forward）
mise run im:test

# 2) 构建 + 部署 IM
mise run release-deploy
# 或：docker build -f deploy/elixir/im/Dockerfile -t im:local .
#     kubectl apply -k deploy/elixir/im/k8s/overlays/local/

# 3) 冒烟
mise run release-smoke

# 4)（可选）多副本
kubectl apply -k deploy/elixir/im/k8s/overlays/cluster/
```

运行时关键环境变量（见 `config/runtime.exs`）：`DATABASE_URL`、`SECRET_KEY_BASE`、`PHX_HOST`、`PHX_SERVER=true`；集群模式另见 `CLUSTER_STRATEGY`、`RELEASE_NODE_MODE`。

---

## 3. 压测 Job

```bash
docker build -f deploy/elixir/loadtest/Dockerfile -t im-loadtest:local .
kubectl apply -f deploy/elixir/loadtest/k8s/job.yaml
kubectl logs -n im job/im-loadtest-connection -f
```

本地（不对 K8s）：

```bash
cd apps/elixir/loadtest
mix deps.get
mix loadtest.run connection_load --app-key app_demo --users 50 --base-url http://localhost:4000
```

压测会通过 **`POST /internal/v1/users/:id/provision`**（`X-IM-Caller-Service: loadtest`）自动建用户；默认密码 `password`。

---

## 4. 健康检查与指标

| 路径 | 用途 |
| --- | --- |
| `GET /health/live` | 进程存活 |
| `GET /health/ready` | 依赖就绪（DB 等） |
| `GET /metrics` | Prometheus 文本（P9-05） |

### CPU 火焰图

排查 CPU 热点时使用 Erlang/OTP 原生 perf（非 trace）：

```bash
kubectl -n im-dev set env deployment/im IM_PERF_FLAMEGRAPH=true
kubectl -n im-dev rollout status deployment/im
mise run flamegraph
```

产出 `artifacts/flamegraph/run-k8s-*/flame_sched.svg`。完整说明见 [flamegraph.md](flamegraph.md)。

---

## 6. Event Bus（Kafka 旁路）

默认 **开启**（`EVENT_BUS_ENABLED=true`）。`mise run k8s-up` 会起 Redpanda；`release-deploy` 另起 IM。生产须配置 `KAFKA_BROKERS`。

**本地 K8s 一键开启**（含 Redpanda）：

```bash
kubectl apply -k deploy/elixir/im/k8s/overlays/kafka-event-bus/
kubectl -n im-dev rollout status deployment/redpanda
kubectl -n im-dev rollout restart deployment/im
```

或 `mise run k8s-kafka-event-bus`（仅应用清单，不构建镜像）。

| 变量 | 说明 |
| --- | --- |
| `EVENT_BUS_ENABLED` | `true` 启用旁路 |
| `KAFKA_BROKERS` | 逗号分隔 broker 列表 |
| `EVENT_BUS_PRODUCER` | `memory`（测试）或 `brod`（生产） |

移动推送 v1 行为见 [mobile-push.md](mobile-push.md)。FCM/APNs **不在** IM 进程内。

---

## 7. Oban Cron（可选）

默认均 **关闭**；通过环境变量在 `runtime.exs` 注册 Cron 插件：

| 变量 | Worker | 默认 Cron |
| --- | --- | --- |
| `UNREAD_FLUSH_AUTO=true` | `IM.Workers.UnreadFlush` | `*/5 * * * *` |
| `PERMISSION_RECONCILE_AUTO=true` | `IM.Workers.PermissionReconcile` | `0 */6 * * *` |
| `TTL_PURGE_AUTO=true` | `IM.Workers.TtlPurge` | 见 `runtime.exs` |

K8s 示例注释见 `deploy/elixir/im/k8s/im/configmap.yaml`。

---

## 8. 上线前检查清单

- [ ] `mise run ci` 绿（含 proto-gen-check、im_client、loadtest）
- [ ] Release 镜像可启动，探针通过
- [ ] 迁移在启动前执行（`bin/migrate`）
- [ ] 多副本时 headless + PDB 已应用
- [ ] Redis 可达（多副本 **必须**；单节点也建议）
- [ ] 按需开启 Event Bus / Oban Cron（§6–§7）
- [ ] 压测基线报告已归档（见 [`loadtest-report.md`](loadtest-report.md)）
- [ ] 故障演练项已读（[`fault-drill.md`](fault-drill.md)）
- [ ] Protocol checklist 勾选（[`protocol-regression-checklist.md`](protocol-regression-checklist.md)）
