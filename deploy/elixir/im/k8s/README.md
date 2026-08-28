# 本地 Kubernetes 环境（OrbStack + kubectl）

本目录提供 **本地开发与集成测试** 用的 Kubernetes 清单。团队默认使用 [OrbStack](https://orbstack.dev/) 自带的 K8s 集群。

> **验收黄金路径**：功能必须以 **Release 镜像 + K8s 部署** 验证，与线上一致。详见 [`docs/implementation/elixir/release-deploy-test.md`](../../docs/implementation/elixir/release-deploy-test.md)。

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

---

## 多副本联调

```bash
kubectl -n im-dev scale deployment/im --replicas=2
kubectl -n im-dev get pods -l app=im
```

**在 scale 之前**须调整分布式 Erlang，见下一节。Phase 9（P9-01 / P9-01b）与线上一致。

---

## 分布式 Erlang 与多副本

`overlays/local` 默认 **单副本**，ConfigMap 使用 `RELEASE_NODE=im@127.0.0.1`（所有 Pod 共享同一节点名，**仅 replicas=1 安全**）。

| 场景 | `RELEASE_DISTRIBUTION` | `RELEASE_NODE` | 发现方式 |
| --- | --- | --- | --- |
| **本地单副本**（默认） | `name` | `im@127.0.0.1`（ConfigMap） | 无需 libcluster |
| **K8s 多副本**（Phase 9） | `name` | **每 Pod 唯一**，如 `im@<POD_IP>` | libcluster + K8s 标签选择器 |
| **StatefulSet 生产**（可选） | `name` | `im@<pod>.<headless-svc>` | headless Service DNS |

### 多副本必做项

1. **`RELEASE_COOKIE`**：所有 IM Pod 相同，由 `im-runtime` Secret 注入（已预留）。
2. **唯一 `RELEASE_NODE`**：从 ConfigMap 全局值改为 **每 Pod 注入**：
   - Deployment 已通过 `fieldRef` 注入 `POD_IP`、`POD_NAME`（见 `im/deployment.yaml`）。
   - 在 `config/runtime.exs` 中：`System.get_env("RELEASE_NODE") || "im@#{System.get_env("POD_IP")}"`（Phase 0 脚手架时实现）。
   - 或在启动脚本中根据 `POD_IP` 导出 `RELEASE_NODE` 后 `exec bin/im start`。
3. **libcluster**：`Cluster.Strategy.Kubernetes`（或 DNS）发现同命名空间 `app=im` Pod；见 [modular-architecture.md](../../docs/design/modular-architecture.md)、[deploy/elixir/im/README.md](../README.md)。
4. **不要用 `sname@127.0.0.1` 跑多副本**：短名 + 同 IP 会导致节点名冲突、集群分裂。

### 验证

```bash
# 两副本均 Ready 后，进入 Pod 检查节点名互不相同
kubectl -n im-dev exec -it deploy/im -- bin/im rpc 'Node.self() |> IO.inspect()'
kubectl -n im-dev get pods -l app=im -o wide   # 确认 POD_IP 与节点名对应
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
    │   ├── namespace.yaml
    │   └── deps/
    ├── im/
    │   ├── deployment.yaml
    │   ├── service.yaml
    │   ├── configmap.yaml
    │   └── secret.yaml
    └── overlays/
        └── local/              # 全栈入口
```

---

## 常用命令

```bash
kubectl apply -k deploy/elixir/im/k8s/overlays/local/
kubectl delete -k deploy/elixir/im/k8s/overlays/local/
kubectl -n im-dev get pods,svc
kubectl -n im-dev logs -f deployment/im
kubectl -n im-dev exec -it deploy/redis -- redis-cli
kubectl -n im-dev exec -it deploy/postgres -- psql -U im -d im_dev
```

---

## mise 任务

见根目录 [`mise.toml`](../../mise.toml)：`mise run k8s-up`、`k8s-full`、`release-deploy`、`k8s-port-forward`、`release-smoke` 等。`mise tasks` 查看全部。

---

## 相关文档

- [`release-deploy-test.md`](../../docs/implementation/elixir/release-deploy-test.md) — 与线上一致性、DoD
- [`deploy/elixir/im/k8s/README.md`](README.md) — 本目录操作说明
- [`project-structure.md`](../../docs/implementation/elixir/project-structure.md) — 运行时模块布局
- [`roadmap.md`](../../docs/implementation/elixir/roadmap.md)
