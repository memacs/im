# 压测报告说明（P10-01 / P10-02 / LT-33）

## 工具

| 项目 | 路径 |
| --- | --- |
| 客户端库 | `apps/elixir/im_client` |
| 压测服务 | `apps/elixir/loadtest` |
| CLI | `mix loadtest.run <scenario> --app-key …` |
| K8s Job | `deploy/elixir/loadtest/k8s/job.yaml` |

## 用户 bootstrap

压测经 **`POST /internal/v1/users/:user_id/provision`**（`X-IM-Caller-Service: loadtest`）自动建用户，无需手工 seed。

## 如何产出报告

```bash
cd apps/elixir/loadtest && mix deps.get

mix loadtest.run connection_load \
  --app-key app_demo --users 1000 --concurrency 200 \
  --base-url http://localhost:4000 \
  --report reports/connection_load.json

mix loadtest.run message_flood \
  --app-key app_demo --users 50 --iterations 100 \
  --report reports/message_flood.json

mix loadtest.run unread_bump \
  --app-key app_demo --users 50 --iterations 100 --polls 30 \
  --read-every 5 --report reports/unread_bump.json
```

JSON 字段：`duration_ms`、`qps`、`ops.*.success_rate`、`ops.*.latency.{p50,p90,p99}_ms`、`errors`。

## 目标与状态

| 目标 | Roadmap | 状态 |
| --- | --- | --- |
| 单节点 3–5 万连接 | P10-01 | **工具已交付**；达标依赖机器 `ulimit`/Bandit 调优，需在目标环境实测后粘贴 JSON |
| 单聊 QPS / ACK 延迟 | P10-02 基线 | 场景 `message_flood` 已交付 |
| 大群扇出 P99&lt;200ms | P10-02 / LT-30 | **工具已交付**；5000 人群达标需目标环境实测归档 |
| 未读 bump + 会话列表 | LT-33 | **工具已交付**；本地 dev 50 用户 QPS ~500 仅供参考 |

## 已知瓶颈方向（预置）

1. **FD / 端口**：压测机与 IM 节点需提高 `nofile`；容器需对应 `securityContext`。
2. **AUTH 路径 DB**：每连接登录+鉴权打 DB；大规模连接应预热 token 或依赖 provision 批创用户。
3. **单节点进程**：BEAM 调度与 Bandit accept 队列；超 1 万连接建议先水平扩展再冲 5 万。
4. **消息路径**：`message_flood` 含持久化；纯内存扇出另测 LT-30。

## 归档

将当次 `reports/*.json` 与环境说明（CPU/内存/副本数/Redis 开关）附在发布记录中。
