# 本地 Kubernetes 环境（OrbStack + kubectl）

本目录提供 **本地开发与集成测试** 用的 Kubernetes 清单。团队默认使用 [OrbStack](https://orbstack.dev/) 自带的 K8s 集群。

> **验收黄金路径**：功能必须以 **Release 镜像 + K8s 部署** 验证，与线上一致。详见 [`docs/implementation/elixir/release-deploy-test.md`](../../../../docs/implementation/elixir/release-deploy-test.md)。

> **仅用于本地/联调**：`im-dev` 命名空间内的 Secret 为开发占位值，**禁止**用于生产。

---

## 前置条件

| 工具 | 说明 |
| --- | --- |
| [OrbStack](https://orbstack.dev/) | Docker + 内置 Kubernetes |
| `kubectl` | context 一般为 `orbstack` |
| `docker` | `deploy/elixir/im/Dockerfile` 构建 Release 镜像 |

```bash
kubectl config current-context
kubectl cluster-info
```

OrbStack 内 `docker build` 的 `im:local` 可被集群直接拉取（`imagePullPolicy: IfNotPresent`）。

---

## 黄金路径（Release → K8s → Test）

```bash
# 一键
mise run release-deploy

# 或分步
mise run release-build
mise run k8s-full
kubectl -n im-dev rollout status deployment/im
mise run k8s-port-forward   # 另开终端
mise run release-smoke
```

**不要**仅用 `mix phx.server` 作为功能验收（开发调试可以，标 `done` 不行）。

---

## Kustomize 入口

| 路径 | 内容 |
| --- | --- |
| `deploy/elixir/im/k8s/` | 仅依赖（Redis + PostgreSQL） |
| `deploy/elixir/im/k8s/overlays/local/` | **依赖 + IM Release**（集成测试用这个） |
| `deploy/elixir/im/k8s/im/` | IM Deployment / Service / ConfigMap / Secret |
| `deploy/elixir/im/k8s/base/` | 命名空间与依赖基础层 |

```bash
# 只起依赖
kubectl apply -k deploy/elixir/im/k8s/

# 全栈（推荐）
kubectl apply -k deploy/elixir/im/k8s/overlays/local/
```

---

## 服务地址（集群内）

| Service | DNS | 用途 |
| --- | --- | --- |
| `redis` | `redis.im-dev.svc.cluster.local:6379` | 序列号、在线状态 |
| `postgres` | `postgres.im-dev.svc.cluster.local:5432` | 消息与业务数据 |
| `im` | `im.im-dev.svc.cluster.local:4000` | IM Release（WebSocket / HTTP） |

宿主机调试：

```bash
kubectl -n im-dev port-forward svc/im 4000:4000
kubectl -n im-dev port-forward svc/postgres 5432:5432
kubectl -n im-dev port-forward svc/redis 6379:6379
```

`mix test` 连的也是这套 Postgres。`kubectl port-forward` 会在 Pod 重建或空闲时断开，
用带自动重连的常驻任务省事：

```bash
mise run pg-forward                       # 终端 A，常驻
mise run test                             # 终端 B（自动 PGPORT）
```

---

## 安全加固基线

清单按 Pod Security Standards **restricted** 编写，`im-dev` 命名空间上打了
`pod-security.kubernetes.io/enforce=restricted`——本地就按生产口径校验，
免得加固缺口留到上线才暴露。

| 项 | 配置 |
| --- | --- |
| 身份 | `runAsNonRoot: true`、`runAsUser/Group: 65534`（与 Dockerfile 的 `USER nobody:nogroup` 一致） |
| 权限 | `allowPrivilegeEscalation: false`、`capabilities.drop: [ALL]`、`seccompProfile: RuntimeDefault` |
| 文件系统 | `readOnlyRootFilesystem: true` + `/tmp` emptyDir |
| API 访问 | `automountServiceAccountToken: false`（IM 不调 K8s API；P9-01 上 libcluster 时需按需放开并配 RBAC） |
| 密钥 | `DATABASE_URL`、`SECRET_KEY_BASE`、`RELEASE_COOKIE` 在 Secret `im-runtime`，不在 ConfigMap |

**只读根文件系统与 Elixir Release**：`bin/im start` 需要一个可写的临时目录写
`vm.args`、启动脚本产物等，默认在 `$RELEASE_ROOT/tmp`（即只读的 `/app`）。
Deployment 因此设 `RELEASE_TMP=/tmp` 并挂 emptyDir，`bin/im eval`、`bin/migrate` 同样依赖它。

**优雅停机**：`terminationGracePeriodSeconds: 60` + `preStop: sleep 5`。
Endpoint 摘除是异步的，Pod 被标记 Terminating 后仍可能收到几秒流量，
先 sleep 再让应用开始关闭。配合 `maxUnavailable: 0`，滚动更新时先起新 Pod 再摘旧 Pod。
真正的连接 drain（通知客户端重连）在 Phase 9 补。

> **尚未做（可选）**：镜像 digest 固定。  
> **Kafka 旁路（按需）**：`overlays/kafka-event-bus/` 含 Redpanda + ConfigMap 补丁，见 [`deploy-guide.md`](../../../../docs/implementation/elixir/deploy-guide.md) §6。  
> **cluster overlay 已含**：`PodDisruptionBudget`、`HorizontalPodAutoscaler`、`NetworkPolicy`（见 `im/networkpolicy.yaml`）。

---

## 多副本联调（P9-01b）

推荐使用 **`overlays/cluster`**（replicas=2 + headless + libcluster DNS + PDB）：

```bash
mise run release-build
kubectl apply -k deploy/elixir/im/k8s/overlays/cluster/
kubectl -n im-dev rollout status deployment/im
kubectl -n im-dev get pods,svc -l app=im
```

| 资源 | 作用 |
| --- | --- |
| `im-headless` | `clusterIP: None`，供 `Cluster.Strategy.Kubernetes.DNS` |
| `RELEASE_NODE_MODE=pod_ip` | `rel/env.sh.eex` 导出 `RELEASE_NODE=im@$POD_IP` |
| `CLUSTER_STRATEGY=kubernetes` | runtime 装配 libcluster topologies |
| `PodDisruptionBudget` | `minAvailable: 1` |

单副本日常联调仍用 `overlays/local`。

---

## 分布式 Erlang 与多副本

`overlays/local` 默认 **单副本**，ConfigMap 使用 `RELEASE_NODE=im@127.0.0.1`（所有 Pod 共享同一节点名，**仅 replicas=1 安全**）。

| 场景 | `RELEASE_DISTRIBUTION` | `RELEASE_NODE` | 发现方式 |
| --- | --- | --- | --- |
| **本地单副本**（`overlays/local`） | `name` | `im@127.0.0.1`（ConfigMap） | 无需 libcluster |
| **K8s 多副本**（`overlays/cluster`） | `name` | **每 Pod** `im@<POD_IP>`（`RELEASE_NODE_MODE=pod_ip`） | libcluster + `im-headless` DNS |
| **StatefulSet 生产**（可选） | `name` | `im@<pod>.<headless-svc>` | headless Service DNS |

### 多副本必做项

1. **`RELEASE_COOKIE`**：所有 IM Pod 相同，由 `im-runtime` Secret 注入（已预留）。
2. **唯一 `RELEASE_NODE`**：`rel/env.sh.eex` 在 `RELEASE_NODE_MODE=pod_ip` 时用 `POD_IP` 覆盖。
3. **libcluster**：`CLUSTER_STRATEGY=kubernetes` + `CLUSTER_SERVICE=im-headless`。
4. **不要用 `sname@127.0.0.1` 跑多副本**：短名 + 同 IP 会导致节点名冲突、集群分裂。

### 验证 checklist

```bash
# 1. 两副本 Ready，节点名互不相同
kubectl -n im-dev get pods -l app=im -o wide
kubectl -n im-dev exec deploy/im -- printenv RELEASE_NODE POD_IP RELEASE_NODE_MODE

# 2. BEAM 已互连（任选一 Pod）
kubectl -n im-dev exec deploy/im -- bin/im rpc 'IO.inspect({Node.self(), Node.list()})'
# 期望：{:"im@<ip1>", [:"im@<ip2>"]}

# 3. UserTracker 跨 Pod（登录 A 在 pod1，从 pod2 查 presence — 手工联调）
# 4. /metrics 两副本均可 scrape
kubectl -n im-dev exec deploy/im -- wget -qO- http://127.0.0.1:4000/metrics | head
```

---

## 目录结构

```text
deploy/elixir/im/
├── Dockerfile
├── scripts/release-deploy-local.sh
└── k8s/
    ├── kustomization.yaml      # → base（仅依赖）
    ├── base/
    │   ├── namespace.yaml      # 含 PSS restricted 标签
    │   └── deps/               # postgres / redis StatefulSet + PVC
    ├── im/
    │   ├── deployment.yaml
    │   ├── service.yaml
    │   ├── service-headless.yaml
    │   ├── configmap.yaml
    │   └── secret.yaml
    └── overlays/
        ├── local/              # 全栈单副本
        └── cluster/            # 多副本 + libcluster + PDB（P9-01b）
```

---

## 常用命令

```bash
kubectl apply -k deploy/elixir/im/k8s/overlays/local/
kubectl delete -k deploy/elixir/im/k8s/overlays/local/
kubectl -n im-dev get pods,svc
kubectl -n im-dev logs -f deployment/im
# redis/postgres 是 StatefulSet（带 PVC），不是 Deployment
kubectl -n im-dev exec -it redis-0 -- redis-cli
kubectl -n im-dev exec -it postgres-0 -- psql -U im -d im_dev
```

依赖栈用 StatefulSet + `volumeClaimTemplates`，重启不丢数据。Redis 开了 AOF：
它是 `conv_seq` / `inbox_seq` 的权威发号源，重启丢号会让序列回退，客户端据此判重会错乱。

```bash
kubectl -n im-dev get pvc                       # 查看卷
kubectl -n im-dev delete pvc data-postgres-0    # 需要清库时（会丢数据）
```

---

## mise 任务

见根目录 [`mise.toml`](../../../../mise.toml)：`mise run k8s-up`、`k8s-full`、`release-deploy`、`k8s-port-forward`、`release-smoke` 等。`mise tasks` 查看全部。

---

## 相关文档

| 文档 | 说明 |
| --- | --- |
| [docs/README.md](../../../../docs/README.md) | 文档总索引 |
| [deploy/README.md](../../../README.md) | 部署总览 |
| [apps/elixir/im/README.md](../../../../apps/elixir/im/README.md) | 环境变量、集群模式详解 |
| [release-deploy-test.md](../../../../docs/implementation/elixir/release-deploy-test.md) | 与线上一致性、DoD |
| [deploy-guide.md](../../../../docs/implementation/elixir/deploy-guide.md) | 生产部署 §6–§8 |
| [project-structure.md](../../../../docs/implementation/elixir/project-structure.md) | 运行时模块布局 |
| [fault-drill.md](../../../../docs/implementation/elixir/fault-drill.md) | 故障演练 |
| [roadmap.md](../../../../docs/implementation/elixir/roadmap.md) | Phase 9 集群任务 |
