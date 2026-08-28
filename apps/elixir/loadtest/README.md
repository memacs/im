# 压测服务（Elixir）

独立 Mix 项目 + Release：对 IM 集群施加连接、消息、群扇出、Channel 订阅、未读等场景压测。

| 项 | 说明 |
| --- | --- |
| 命名空间 | `IM.LoadTest.*` |
| 依赖 | `{:im_client, path: "../im_client"}`，**不**依赖 `im` |
| 部署 | `deploy/elixir/loadtest/`（独立镜像 + K8s Job） |

报告与场景说明：[loadtest-report.md](../../../docs/implementation/elixir/loadtest-report.md)  
Kiro Spec：[phase-10-loadtest-ops](../../../docs/specs-index.md#phase-013主路线图) · [`.kiro/specs/phase-10-loadtest-ops/`](../../../.kiro/specs/phase-10-loadtest-ops/)

---

## 前置条件

- mise + Elixir（与 IM 同版本）
- **目标 IM 已可达**（本地 port-forward 或集群内 `svc/im`）
- IM 须开启 `POST /internal/v1/users/:id/provision`（压测自动建用户，默认密码 `password`）

---

## 启动

### 本地 CLI（不对 K8s 打 Job）

```bash
cd apps/elixir/loadtest
mix deps.get

# 连接压测
mix loadtest.run connection_load \
  --app-key app_demo \
  --users 50 \
  --base-url http://localhost:4000

# 消息 flood
mix loadtest.run message_flood \
  --app-key app_demo \
  --users 10 \
  --iterations 20 \
  --base-url http://localhost:4000

# 大群扇出 / 聊天室 / Channel / 未读 等见 loadtest-report.md
```

仓库根快捷命令：

```bash
mise run loadtest:test
mise run loadtest:run -- connection_load --app-key app_demo --users 50 --base-url http://localhost:4000
```

### 本地 Release 试跑

```bash
cd apps/elixir/loadtest
MIX_ENV=prod mix release
_build/prod/rel/loadtest/bin/loadtest eval "IO.inspect(:ok)"
```

---

## 配置

### CLI / 环境变量

| 参数 / 变量 | 说明 | 默认 |
| --- | --- | --- |
| `--app-key` / `APP_KEY` | 租户 | 必填 |
| `--base-url` / `BASE_URL` | IM HTTP 基址 | `http://localhost:4000` |
| `--users` / `USERS` | 虚拟用户数 | 场景相关 |
| `--iterations` / `ITERATIONS` | 每用户迭代 | 场景相关 |
| `--password` / `PASSWORD` | provision 用户密码 | `password` |
| `--scenario` / `SCENARIO` | 场景名 | Job 中指定 |
| `REPORT` | JSON 报告路径 | 可选 |

场景列表：`connection_load`、`message_flood`、`group_fanout`、`room_broadcast`、`channel_subscribe`、`unread_bump` 等。

### Mix 配置

`config/config.exs` / `config/runtime.exs`：Oban、日志级别等；**压测目标地址以 CLI 参数为准**。

---

## 线上部署

压测与 **IM 生产 Deployment 分离**，以 K8s **Job** 对集群内 Service 施压。

### 构建镜像

```bash
docker build -f deploy/elixir/loadtest/Dockerfile -t im-loadtest:<tag> .
```

### 运行 Job

```bash
# 编辑 job.yaml 中的 SCENARIO / USERS / BASE_URL 等
kubectl apply -f deploy/elixir/loadtest/k8s/job.yaml
kubectl -n im-dev logs -f job/im-loadtest-unread-bump
```

Job 默认：

- `BASE_URL=http://im.im-dev.svc.cluster.local:4000`（集群内 DNS）
- `APP_KEY=app_demo`
- 入口：`/app/bin/run_loadtest`

### 注意事项

- 压测前确认 IM `rollout` 完成且 `/health/ready` 正常
- 大规模压测建议在独立命名空间/窗口执行，避免与生产流量混跑
- 报告归档见 [loadtest-report.md](../../../docs/implementation/elixir/loadtest-report.md)

---

## 相关文档

- [文档总索引](../../../docs/README.md)
- [功能模块对照表](../../../docs/module-map.md)
- [Kiro Spec 索引](../../../docs/specs-index.md)
- [deploy/elixir/loadtest/README.md](../../../deploy/elixir/loadtest/README.md)
- [deploy-guide.md §3](../../../docs/implementation/elixir/deploy-guide.md)
- [im_client README](../im_client/README.md)
- [apps 总览](../../README.md)
