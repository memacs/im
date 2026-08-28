# IM Elixir 部署

按 **应用** 分子目录，与 `apps/elixir/` 一一对应。

| 应用 | 路径 | 说明 |
| --- | --- | --- |
| **IM 主服务** | [im/](im/) | Release 镜像 + K8s（当前可用） |
| **压测** | [loadtest/](loadtest/) | 独立 Job 镜像 + K8s Job |

文档导航：[docs/README.md](../../docs/README.md) · [deploy-guide.md](../../docs/implementation/elixir/deploy-guide.md) · [apps/elixir/](../../apps/elixir/README.md)

---

## IM 主服务（im/）

| 项 | 路径 |
| --- | --- |
| Dockerfile | `deploy/elixir/im/Dockerfile`（构建上下文 = **仓库根**） |
| K8s 清单 | `deploy/elixir/im/k8s/` |
| 入口 | `/app/bin/im start` |
| 迁移 | `kubectl exec … -- /app/bin/migrate` |

```bash
mise run release-deploy
mise run k8s-port-forward
mise run release-smoke
mise run im:test-smoke
```

| 文档 | 说明 |
| --- | --- |
| [im/k8s/README.md](im/k8s/README.md) | K8s 操作、overlay、多副本 |
| [release-deploy-test.md](../../docs/implementation/elixir/release-deploy-test.md) | 验收黄金路径 |
| [apps/elixir/im/README.md](../../apps/elixir/im/README.md) | 环境变量、集群模式详解 |
| [deploy-guide.md](../../docs/implementation/elixir/deploy-guide.md) | 生产部署 §6–§8 |

---

## 压测（loadtest/）

独立 Release，对集群内 `svc/im` 施压：

```bash
docker build -f deploy/elixir/loadtest/Dockerfile -t im-loadtest:local .
kubectl apply -f deploy/elixir/loadtest/k8s/job.yaml
```

详见 [loadtest/README.md](loadtest/README.md) 与 [loadtest-report.md](../../docs/implementation/elixir/loadtest-report.md)。

---

## 部署原则

1. **镜像按应用拆分**：IM 与 loadtest 不共用 Dockerfile
2. **配置外置**：ConfigMap / Secret
3. **健康检查**：存活 `GET /health/live`（不查库）与就绪 `GET /health/ready`（查主库）分离
4. **资源限制**：requests / limits；PSS restricted 基线见 [k8s/README.md](im/k8s/README.md)

---

## 相关链接

- [deploy/README.md](../README.md)
- [monorepo-layout.md](../../docs/implementation/monorepo-layout.md)
- [specs-index.md](../../docs/specs-index.md)（Phase 9–10 部署相关 spec）
