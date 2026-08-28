---
name: im-k8s-debug
description: >-
  通过 kubectl 进入 K8s IM Release Pod，用 bin/im rpc/eval 与结构化日志（trace_id / event）
  排查线上或本地集群问题。用户提到 K8s 排障、Pod 日志、trace 追踪、Release RPC、
  im-dev 调试、消息投递失败、连接/集群状态时优先使用。
auto_suggest: true
---

# IM K8s 排障（RPC + 日志）

在 **Release 容器**内检查运行态；**不要**用 `mix run` / dev server 代替 Pod 内观测。

| 项 | 说明 |
| --- | --- |
| 命名空间 | `im-dev`（默认） |
| 工作目录 | `/app` |
| RPC 入口 | `/app/bin/im rpc '...'` |
| 一次性 eval | `/app/bin/im eval "..."`（迁移、冒烟） |
| 日志规范 | [observability.md](../../../docs/design/observability.md) §2.6 |
| 实现细节 | [observability 实现](../../../docs/implementation/elixir/observability.md) |
| 详细命令 | [reference.md](reference.md) |

**关联 skill**：CPU 热点 → [`im-flamegraph`](../im-flamegraph/SKILL.md)；指标定义 → [`telemetry-essentials`](../telemetry-essentials/SKILL.md)。

---

## 前置条件

```bash
mise run k8s-status          # Pod 须 Running
mise run release-deploy      # 或 k8s-full（需已构建 im:local 镜像）
```

多副本时先定位 Pod：

```bash
kubectl -n im-dev get pods -l app=im -o wide
POD=im-xxxxx-yyyyy           # 后续 exec 用 pod/$POD 替代 deployment/im
```

---

## Agent 工作流（按顺序）

复制进度清单：

```text
排障进度：
- [ ] 1. 确认 Pod / 就绪 / 最近 rollout
- [ ] 2. 拉日志（按 event / trace_id / 时间窗）
- [ ] 3. RPC 验证节点、连接、配置、依赖
- [ ] 4. 必要时复现（Smoke / 客户端）并交叉验证
- [ ] 5. 汇总：现象 → 证据 → 根因假设 → 下一步
```

### 1. 集群与 Pod 健康

```bash
kubectl -n im-dev rollout status deployment/im
kubectl -n im-dev get pods,svc -l app=im
mise run release-smoke         # 需另开终端 mise run k8s-port-forward
```

### 2. 日志（主排障手段）

```bash
mise run k8s-logs
# 或带时间窗 / 前次崩溃
kubectl -n im-dev logs deployment/im --since=15m
kubectl -n im-dev logs deployment/im --previous
```

**生产默认 `LOG_LEVEL=warning`**：成功路径 **无日志**；只有白名单 `event` 会输出 NDJSON。

按 **trace_id** 串链路（首选）：

```bash
TRACE=550e8400-e29b-41d4-a716-446655440000
kubectl -n im-dev logs deployment/im --since=30m | grep "$TRACE"
```

按 **event** 筛常见失败：

```bash
kubectl -n im-dev logs deployment/im --since=15m | grep -E '"event":"(packet_error|auth_failed|push_failed|storage_failed|internal_error)"'
```

NDJSON 字段见 `IM.Log.JsonFormatter`：`event`、`trace_id`、`app_key`、`user_id`、`cmd`、`code`、`reason`、`caller_module` 等。

**临时提高日志级别**（须 rollout 后生效，`runtime.exs` 启动时读取）：

```bash
kubectl -n im-dev set env deployment/im LOG_LEVEL=info   # 或 debug
kubectl -n im-dev rollout status deployment/im
# 排障后恢复
kubectl -n im-dev set env deployment/im LOG_LEVEL-
kubectl -n im-dev rollout status deployment/im
```

### 3. RPC（运行态探针）

统一形式（**外层单引号**，Elixir 字符串用双引号）：

```bash
kubectl -n im-dev exec deployment/im -- /app/bin/im rpc 'IO.inspect(Node.self())'
```

常用探针：

```bash
# 集群
kubectl -n im-dev exec deployment/im -- /app/bin/im rpc 'IO.inspect({Node.self(), Node.list()})'

# 本节点在线设备
kubectl -n im-dev exec deployment/im -- /app/bin/im rpc 'IO.inspect(IM.Connection.Registry.list_user_devices("app_demo", "USER_ID"))'

# Event Bus / Redis 开关
kubectl -n im-dev exec deployment/im -- /app/bin/im rpc 'IO.inspect(Application.get_env(:im, :event_bus_enabled))'
kubectl -n im-dev exec deployment/im -- /app/bin/im rpc 'IO.inspect(Application.get_env(:im, :redis_url))'

# Prometheus 指标（也可 port-forward 后 curl）
kubectl -n im-dev exec deployment/im -- wget -qO- http://127.0.0.1:4000/metrics | head -40
```

`rpc` 连 **已运行** BEAM；`eval` 用于 **独立启动** 短任务（会起临时节点，勿与 `rpc` 混用查连接表）：

```bash
kubectl -n im-dev exec deployment/im -- /app/bin/im eval "IM.Release.Smoke.messaging()"
kubectl -n im-dev exec deployment/im -- /app/bin/smoke-messaging   # 等价
```

更多配方见 [reference.md](reference.md)。

### 4. trace 闭环

| 步骤 | 动作 |
| --- | --- |
| 拿 trace_id | 客户端 `Packet.trace_id`、REST `X-Trace-Id`、或日志里最近 error |
| 拉日志 | `grep trace_id` 得 `event` + `code` + `reason` + `caller_module` |
| 看指标 | `/metrics` 中 `im.packet.error.total`、`im.push.failed.total` 等（**无** trace 标签） |
| RPC 验证 | 用户是否在线、配置是否一致、依赖是否可达 |
| 复现 | `release-smoke-messaging` / `im_client` E2E |

设计约束：**禁止**把 `trace_id` / `user_id` 作 Prometheus 标签；单条排障靠日志。

### 5. 汇报模板

```markdown
## 排障摘要

**现象**：（用户可见行为）
**环境**：im-dev / Pod / 副本数 / 最近变更
**证据**：
- 日志：（trace_id、event、reason 摘录）
- RPC：（节点、在线设备、配置）
- 指标：（相关 counter 是否上涨）
**根因假设**：
**建议**：（代码修复 / 配置 / 依赖 / 复现步骤）
```

---

## 常见场景速查

| 症状 | 日志 event | RPC / 其他 |
| --- | --- | --- |
| WS 鉴权失败 | `auth_failed` | 查 token / `Session`；注意采样 |
| 协议错误 | `packet_error` | 看 `code`、`ref_cmd` |
| 消息未推到端 | `push_failed` | `Connection.Registry.list_user_devices/2` |
| 写库失败 | `storage_failed` | `bin/migrate`、Postgres 连通 |
| 跨节点扇出 | `cluster_dispatch_failed` | `Node.list()`、多副本是否就绪 |
| Event Bus | `event_bus` 相关 metric | `event_bus_enabled`、`KAFKA_BROKERS` |
| 限流 | `rate_limited` | 采样；查 `rate_limiter` 配置 |

---

## 禁止事项

- **不要**在 Pod 外 `mix run` 查 Registry / 连接状态（与 Release 节点隔离）
- **不要**用 `eval` 查本节点 WebSocket 连接（eval 非运行中节点）
- **不要**长期 `LOG_LEVEL=debug` 于生产等价环境（日志量与敏感字段）
- **不要**在 RPC 中执行不可逆写操作（除非用户明确要求）
- CPU 热点用 **perf 火焰图**，见 [`im-flamegraph`](../im-flamegraph/SKILL.md)

---

## mise 快捷命令

| 命令 | 用途 |
| --- | --- |
| `mise run k8s-status` | Pod / Service |
| `mise run k8s-logs` | 跟踪 IM 日志 |
| `mise run k8s-port-forward` | 本机 :4000 |
| `mise run release-smoke` | 健康检查 |
| `mise run release-smoke-messaging` | Pod 内消息冒烟 |
| `mise run release-smoke-auth` | Pod 内鉴权冒烟 |
