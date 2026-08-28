# Elixir 应用

| 目录 | 说明 | Roadmap |
|------|------|---------|
| [im/](im/) | 主 IM 服务（Phoenix Release） | P0-01 起 |
| [loadtest/](loadtest/) | 压测服务 / CLI | Phase 10（P10-01/02） |
| [im_client/](im_client/) | 共享协议客户端（可选） | Phase 2+ 抽出 |

布局说明见 [docs/implementation/monorepo-layout.md](../../docs/implementation/monorepo-layout.md)。

P0-01 创建项目：

```bash
cd apps/elixir/im && mix new im --sup
```
