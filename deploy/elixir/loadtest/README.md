# Elixir 压测部署（Phase 10）

压测服务 **独立** 于 IM 生产 Deployment：

- `Dockerfile`：构建 `apps/elixir/loadtest` Release（待 P10 添加）
- `k8s/job.yaml`：对集群内 `svc/im` 跑连接/消息压测

IM 主服务部署见 [../im/](../im/)。
