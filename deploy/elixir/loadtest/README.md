# Elixir 压测部署

压测服务 **独立** 于 IM 生产 Deployment，以 K8s **Job** 对集群内 Service 施压。

| 项 | 路径 |
| --- | --- |
| Dockerfile | `deploy/elixir/loadtest/Dockerfile` |
| K8s Job | `deploy/elixir/loadtest/k8s/job.yaml` |
| Mix 项目 | `apps/elixir/loadtest/` |
| 协议客户端 | `apps/elixir/im_client/`（path 依赖） |

---

## 构建与运行

```bash
# 构建镜像（仓库根）
docker build -f deploy/elixir/loadtest/Dockerfile -t im-loadtest:local .

# 运行 Job（编辑 job.yaml 中的 SCENARIO / USERS 等）
kubectl apply -f deploy/elixir/loadtest/k8s/job.yaml
kubectl -n im-dev logs -f job/im-loadtest-unread-bump
```

### 本地 CLI（不对 K8s 打 Job）

```bash
mise run loadtest:run -- connection_load \
  --app-key app_demo --users 50 --base-url http://localhost:4000
```

---

## 环境变量（Job / CLI）

| 变量 | 说明 | 默认 |
| --- | --- | --- |
| `APP_KEY` | 租户 | 必填 |
| `BASE_URL` | IM HTTP 基址 | Job 内 `http://im.im-dev.svc.cluster.local:4000` |
| `SCENARIO` | 场景名 | `connection_load` 等 |
| `USERS` | 虚拟用户数 | 场景相关 |
| `ITERATIONS` | 每用户迭代 | 场景相关 |
| `PASSWORD` | provision 密码 | `password` |
| `REPORT` | JSON 报告路径 | 可选 |

场景列表见 [loadtest-report.md](../../../docs/implementation/elixir/loadtest-report.md)。

---

## 前置条件

- 目标 IM 已 `rollout` 完成且 `/health/ready` 正常
- IM 须开启 `POST /internal/v1/users/:id/provision`（压测自动建用户）
- 大规模压测建议在独立窗口执行

---

## 文档导航

| 文档 | 说明 |
| --- | --- |
| [apps/elixir/loadtest/README.md](../../../apps/elixir/loadtest/README.md) | CLI 场景、Release 试跑 |
| [loadtest-report.md](../../../docs/implementation/elixir/loadtest-report.md) | 报告与指标 |
| [loadtest-stability.md](../../../docs/implementation/elixir/loadtest-stability.md) | 长时间稳定性 |
| [deploy-guide.md §3](../../../docs/implementation/elixir/deploy-guide.md) | 压测部署章节 |
| [specs-index](../../../docs/specs-index.md) | [phase-10-loadtest-ops](../../../.kiro/specs/phase-10-loadtest-ops/) |

---

## 相关链接

- [deploy/elixir/README.md](../README.md)
- [deploy/elixir/im/](../im/) — IM 主服务部署
- [deploy/README.md](../../README.md)
