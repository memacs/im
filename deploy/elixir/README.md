# IM Elixir 部署

按 **应用** 分子目录，与 `apps/elixir/` 一一对应。

| 应用 | 路径 | 说明 |
|------|------|------|
| **IM 主服务** | [im/](im/) | Release 镜像 + K8s（当前可用） |
| **压测** | [loadtest/](loadtest/) | Phase 10：Job 镜像（预留） |

仓级说明：[docs/implementation/monorepo-layout.md](../../docs/implementation/monorepo-layout.md)

---

## IM 主服务（im/）

- **镜像**：`deploy/elixir/im/Dockerfile`（构建上下文 = **仓库根**）
- **编排**：`deploy/elixir/im/k8s/`
- **运行**：`/app/bin/im start`

```bash
mise run release-deploy
mise run k8s-port-forward
mise run release-smoke
```

详见 [im/k8s/README.md](im/k8s/README.md) 与 [docs/implementation/elixir/release-deploy-test.md](../../docs/implementation/elixir/release-deploy-test.md)。

---

## 部署原则

1. **镜像按应用拆分**：IM 与 loadtest 不共用 Dockerfile
2. **配置外置**：ConfigMap / Secret
3. **健康检查**：存活 `GET /health/live`（不查库）与就绪 `GET /health/ready`（查主库）分离
4. **资源限制**：requests / limits

---

## 相关链接

- [deploy/README.md](../README.md)
- [apps/elixir/im/README.md](../../apps/elixir/im/README.md)
