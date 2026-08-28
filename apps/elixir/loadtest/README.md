# 压测服务（Elixir）

独立 Mix 项目：连接压测、消息 QPS、扇出延迟（Phase 10）。

- **不**与 `apps/elixir/im` 共用 Release 镜像
- 依赖 `apps/elixir/im_client`（可选），**不**依赖完整 `im` 应用
- 部署：`deploy/elixir/loadtest/`（K8s Job，Phase 10）

设计参考：[test-client.md](../../../docs/implementation/elixir/test-client.md)、roadmap P10-01/02。
