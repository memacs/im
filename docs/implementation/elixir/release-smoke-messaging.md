# Release 消息与会话冒烟（L5）

依赖：集群已部署、`kubectl port-forward` 或集群内访问、`im` Deployment 就绪。

## 路径

```bash
# 终端 1
mise run k8s-port-forward

# 终端 2：健康 + 容器内服务层冒烟
chmod +x deploy/elixir/im/scripts/release-smoke-messaging.sh
./deploy/elixir/im/scripts/release-smoke-messaging.sh
```

等价 mise 任务：

```bash
mise run release-smoke-messaging
```

## 覆盖项

| 步骤 | 说明 |
|------|------|
| `GET /health/live` | 存活 |
| `GET /health/ready` | 就绪（含 DB） |
| `bin/smoke-messaging` | 容器内 `IM.Release.Smoke.messaging/0` |

容器内冒烟（不经过 HTTP，直连 Service 层）：

1. 创建两个临时用户
2. 单聊发消息
3. 收件方 `Conversation.list` → `total_unread >= 1`
4. `MessageRead.mark` → 未读清零
5. `Session.create` 登录路径

成功输出：`SMOKE MESSAGING OK`

## 环境变量

| 变量 | 默认 | 说明 |
|------|------|------|
| `BASE_URL` | `http://localhost:4000` | 健康检查地址 |
| `IM_K8S_NAMESPACE` | `im-dev` | kubectl 命名空间 |
| `SMOKE_SKIP_K8S` | `0` | `1` 时仅 curl 健康，不 exec 进 Pod |
| `SMOKE_APP_KEY` | `app_demo` | 冒烟租户（Pod 内 eval 读取） |
| `SMOKE_PASSWORD` | `smoke_secret` | 临时用户密码 |

## 本地仅 eval（无 K8s）

IM 节点已启动且能连 DB 时：

```bash
cd apps/elixir/im
mix run --no-halt -e ':ok = IM.Release.Smoke.messaging()' 2>/dev/null || \
  mix run -e 'IM.Release.Smoke.messaging()'
```

Release 容器内：

```bash
kubectl -n im-dev exec deployment/im -- /app/bin/smoke-messaging
```

## 与 AUTH 冒烟关系

- [release-smoke-auth.md](release-smoke-auth.md) — 外部 REST+WS 鉴权（需预置用户）
- 本文 — 健康 + **会话/未读/已读** 全链路（Pod 内自建用户）

K8s CronJob 可先后跑两者，或合并到发布流水线。
