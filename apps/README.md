# 应用（apps/）

本目录为 monorepo 内 **可运行或可被依赖** 的实现，与 `proto/`、`docs/`、`deploy/` 并列。

| 路径 | 说明 | 启动 / 部署 |
| --- | --- | --- |
| [elixir/im/](elixir/im/) | IM 主服务（Phoenix） | [README](elixir/im/README.md) |
| [elixir/im_client/](elixir/im_client/) | 协议客户端库 | [README](elixir/im_client/README.md) |
| [elixir/loadtest/](elixir/loadtest/) | 压测 CLI + Job | [README](elixir/loadtest/README.md) |
| [web/im-console/](web/im-console/) | Web 演示控制台 | [README](web/im-console/README.md) |
| [java/im/](java/im/) | Java 实现（预留） | [README](java/im/README.md) |

Elixir 总览：[elixir/README.md](elixir/README.md)

---

## 文档导航

| 文档 | 说明 |
| --- | --- |
| [docs/README.md](../docs/README.md) | **文档总索引**（按角色导航） |
| [docs/module-map.md](../docs/module-map.md) | 功能 ↔ 设计 ↔ 实现 ↔ 代码 ↔ 测试 |
| [docs/specs-index.md](../docs/specs-index.md) | Kiro 阶段规格（`.kiro/specs/`） |
| [monorepo-layout.md](../docs/implementation/monorepo-layout.md) | 单仓 `apps/` + `deploy/` 布局 |
| [deploy-guide.md](../docs/implementation/elixir/deploy-guide.md) | 生产部署指南 |
| [deploy/README.md](../deploy/README.md) | **部署总览**（overlay、镜像、Job） |
| [agent.md](../agent.md) | AI / 协作者硬约束 |

### 各应用 ↔ 文档对照

| 应用 | 设计 | 实现 | Kiro Spec | 部署 |
| --- | --- | --- | --- | --- |
| **elixir/im** | [architecture-overview](../docs/design/architecture-overview.md) | [implementation/elixir/](../docs/implementation/elixir/) · [http-api-reference](../docs/implementation/elixir/http-api-reference.md) | [phase-1–12](../docs/specs-index.md#phase-013主路线图) | [deploy/elixir/im/](../deploy/elixir/im/) |
| **elixir/im_client** | [test-client](../docs/design/test-client.md) | [test-client impl](../docs/implementation/elixir/test-client.md) | [im-client-c0-c1](../.kiro/specs/im-client-c0-c1/) | 不部署 |
| **elixir/loadtest** | [test-client §6](../docs/design/test-client.md) | [loadtest-report](../docs/implementation/elixir/loadtest-report.md) | [phase-10-loadtest-ops](../.kiro/specs/phase-10-loadtest-ops/) | [deploy/elixir/loadtest/](../deploy/elixir/loadtest/) |
| **web/im-console** | [web-console](../docs/design/web-console.md) | [web-console impl](../docs/implementation/web/web-console.md) | [phase-12-web-console](../.kiro/specs/phase-12-web-console/) | 静态 `dist/`（见 app README） |
| **java/im** | 共用 `proto/` | [implementation/java/](../docs/implementation/java/) | — | [deploy/java/](../deploy/java/)（预留） |

---

## 快速命令（仓库根）

```bash
mise install

# IM 主服务
mise run k8s-up && mise run pg-forward   # 终端 A
mise run im:server                        # 终端 B → :4000
mise run release-deploy                   # Release + K8s 验收

# 共享库 / 压测 / Web
mise run im_client:test
mise run im_client:docs              # im_client ExDoc → apps/elixir/im_client/doc/
mise run loadtest:run -- connection_load --app-key app_demo --users 10 --base-url http://localhost:4000
mise run docs                        # 全部 Elixir ExDoc 一次生成
mise run web:dev                          # im-console → :5173
mise run ci                               # 提交前全量检查
```
