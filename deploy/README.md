# IM 部署文档

本目录按 **语言 / 应用** 组织，与 `apps/` 一一对应。见 [monorepo-layout.md](../docs/implementation/monorepo-layout.md)。

| 语言 | 应用 | 部署路径 | App README |
| --- | --- | --- | --- |
| Elixir | IM 主服务 | [elixir/im/](elixir/im/) | [apps/elixir/im/](../apps/elixir/im/README.md) |
| Elixir | 压测 Job | [elixir/loadtest/](elixir/loadtest/) | [apps/elixir/loadtest/](../apps/elixir/loadtest/README.md) |
| Java | IM（预留） | [java/](java/) | [apps/java/im/](../apps/java/im/README.md) |

---

## 文档导航

| 文档 | 说明 |
| --- | --- |
| [docs/README.md](../docs/README.md) | 文档总索引 |
| [docs/module-map.md](../docs/module-map.md) | 功能 ↔ 设计 ↔ 代码 ↔ 测试 |
| [deploy-guide.md](../docs/implementation/elixir/deploy-guide.md) | **生产部署指南（权威）** |
| [release-deploy-test.md](../docs/implementation/elixir/release-deploy-test.md) | Release → K8s → 冒烟验收 |
| [fault-drill.md](../docs/implementation/elixir/fault-drill.md) | 故障演练 |
| [apps/README.md](../apps/README.md) | 应用启动 / 配置说明 |

---

## Elixir IM（当前可用）

```text
elixir/im/
├── Dockerfile                      # 构建上下文 = 仓库根
├── scripts/
│   ├── release-deploy-local.sh
│   ├── release-smoke-auth.sh
│   └── release-smoke-messaging.sh
└── k8s/
    ├── base/                       # redis + postgres（StatefulSet + PVC）
    ├── im/                         # IM Deployment / Service / ConfigMap
    └── overlays/
        ├── local/                  # 单副本全栈（日常验收）
        ├── cluster/                # 多副本 + libcluster + HPA + PDB
        └── kafka-event-bus/        # Redpanda + Event Bus 开启
```

### 一键命令（仓库根）

```bash
mise run release-deploy          # 构建镜像 + overlays/local
mise run k8s-port-forward        # → localhost:4000
mise run release-smoke           # /health/live + /health/ready
mise run release-deploy-cluster  # 多副本 cluster overlay
```

详见 [elixir/im/k8s/README.md](elixir/im/k8s/README.md) 与 [apps/elixir/im/README.md](../apps/elixir/im/README.md) §集群模式。

---

## Elixir 压测（独立 Job）

```bash
docker build -f deploy/elixir/loadtest/Dockerfile -t im-loadtest:local .
kubectl apply -f deploy/elixir/loadtest/k8s/job.yaml
```

详见 [elixir/loadtest/README.md](elixir/loadtest/README.md)。

---

## Overlay 速查

| Overlay | 副本 | libcluster | 用途 |
| --- | --- | --- | --- |
| `overlays/local` | 1 | 关 | 日常开发、功能冒烟 |
| `overlays/cluster` | 2（HPA 2–6） | 开 | 多节点扇出、滚动发布验收 |
| `overlays/kafka-event-bus` | 1 + Redpanda | 关 | Kafka 旁路联调 |

---

## 部署原则

1. **镜像按应用拆分**：IM 与 loadtest 不共用 Dockerfile
2. **配置外置**：ConfigMap / Secret；生产 Secret 禁止用 `im-dev` 占位值
3. **健康检查分离**：`/health/live`（不查库）vs `/health/ready`（查主库）
4. **验收黄金路径**：功能 `done` 须 Release 镜像 + K8s 验证，不用 `mix phx.server` 代替

---

## 相关链接

- [Elixir 部署子目录](elixir/README.md)
- [Java 部署（预留）](java/README.md)
- [agent.md](../agent.md)
