# Elixir 应用

本目录包含 IM  monorepo 下全部 Elixir 项目。

| 目录 | 说明 | 独立部署 | README |
| --- | --- | --- | --- |
| [im/](im/) | 主 IM 服务（Phoenix Release） | ✅ `deploy/elixir/im/` | [im/README.md](im/README.md) |
| [im_client/](im_client/) | 协议客户端共享库 | ❌ 库，无进程 | [im_client/README.md](im_client/README.md) |
| [loadtest/](loadtest/) | 压测 CLI + Release | ✅ `deploy/elixir/loadtest/` | [loadtest/README.md](loadtest/README.md) |

布局说明：[monorepo-layout.md](../../docs/implementation/monorepo-layout.md)

文档导航：[docs/README.md](../../docs/README.md) · [module-map.md](../../docs/module-map.md) · [specs-index.md](../../docs/specs-index.md)

---

## 快速启动（仓库根）

```bash
mise install

# IM 主服务（开发）
mise run k8s-up && mise run pg-forward    # 终端 A
mise run im:server                          # 终端 B → :4000

# IM 主服务（Release 验收）
mise run release-deploy
mise run k8s-port-forward

# IM 集群模式（多副本 + libcluster）
mise run release-deploy-cluster

# 共享库 / 压测
mise run im_client:test
mise run loadtest:run -- connection_load --app-key app_demo --users 10 --base-url http://localhost:4000
```

Web 控制台在 `apps/web/im-console/`，见 [im-console README](../web/im-console/README.md)。

---

## 配置与部署总览

| 应用 | 配置入口 | 线上部署 |
| --- | --- | --- |
| **im** | `config/config.exs` + `config/runtime.exs`；K8s ConfigMap/Secret | [deploy/elixir/im/](../../deploy/elixir/im/) |
| **im_client** | 无独立运行时配置 | 不部署 |
| **loadtest** | CLI 参数 + `config/`；Job env | [deploy/elixir/loadtest/](../../deploy/elixir/loadtest/) |

详细文档：[deploy-guide.md](../../docs/implementation/elixir/deploy-guide.md)
