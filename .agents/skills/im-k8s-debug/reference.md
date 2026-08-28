# IM K8s 排障 — RPC 与日志参考

Pod 内命令默认前缀：

```bash
NS=im-dev
TARGET=deployment/im          # 或 pod/im-xxxxx-yyyyy
exec() { kubectl -n "$NS" exec "$TARGET" -- /app/bin/im rpc "$1"; }
```

---

## rpc vs eval

| 命令 | 连接对象 | 适用 |
| --- | --- | --- |
| `bin/im rpc 'expr'` | **运行中** Release 节点 | Registry、Application、:sys、Supervisor |
| `bin/im eval "expr"` | 临时启动、跑完退出 | `IM.Release.migrate()`、`IM.Release.Smoke.*` |
| `bin/migrate` | eval 包装 | 数据库迁移 |
| `bin/smoke-messaging` | eval 包装 | 消息链路冒烟 |

---

## 集群与 BEAM

```bash
exec 'IO.inspect({Node.self(), Node.list(), node()})'
exec ':net_adm.names() |> IO.inspect()'
exec 'Application.started_applications() |> Enum.filter(fn {a,_,_} -> a == :im end) |> IO.inspect()'
```

多副本：连接表 **仅本 Pod**；跨 Pod 用户须结合 Redis 在线状态或换 Pod exec。

---

## 连接与会话

```bash
# 替换 app_key / user_id / device_id
exec 'IM.Connection.Registry.list_user_devices("app_demo", "alice") |> IO.inspect()'
exec 'IM.Connection.Registry.lookup_device("app_demo", "alice", "dev-1") |> IO.inspect()'

# Registry 计数（本节点）
exec 'Registry.count(IM.Connection.DeviceRegistry) |> IO.inspect()'
exec 'Registry.count(IM.Connection.UserRegistry) |> IO.inspect()'
```

---

## 配置与环境

```bash
exec '[:event_bus_enabled, :event_bus_producer, :redis_url, :node_role] |> Enum.map(fn k -> {k, Application.get_env(:im, k)} end) |> IO.inspect()'
exec 'Application.get_env(:im, IMWeb.Endpoint) |> Keyword.take([:url, :http]) |> IO.inspect()'
exec 'System.get_env("KAFKA_BROKERS") |> IO.inspect()'
exec 'System.get_env("LOG_LEVEL") |> IO.inspect()'
```

容器 env 也可：

```bash
kubectl -n im-dev exec deployment/im -- printenv RELEASE_NODE POD_IP RELEASE_NODE_MODE CLUSTER_STRATEGY DATABASE_URL REDIS_URL KAFKA_BROKERS EVENT_BUS_ENABLED LOG_LEVEL
```

---

## 依赖探针

```bash
# Redis PING
exec ':ok = Redix.command(IM.Cache.Redis.Conn, ["PING"]) |> IO.inspect()'

# Postgres（轻量）
exec 'IM.Repo.query!("SELECT 1") |> Map.take([:num_rows]) |> IO.inspect()'

# Oban 队列概览
exec 'Oban.check_queue(queue: :default) |> IO.inspect()'
```

依赖模块名以当前 Application 为准；Redix 进程名为 `IM.Cache.Redis.Conn`。

---

## 进程 / Supervisor

```bash
exec ':sys.get_status(IM.Telemetry.Supervisor) |> elem(2) |> elem(1) |> IO.inspect()'
exec 'Supervisor.which_children(IM.Telemetry.Supervisor) |> IO.inspect(limit: :infinity)'
exec 'Process.info(self(), [:message_queue_len, :memory]) |> IO.inspect()'
```

---

## 指标

```bash
kubectl -n im-dev exec deployment/im -- wget -qO- http://127.0.0.1:4000/metrics | grep -E '^im_(packet|push|connection|event_bus)'
```

或 port-forward 后本机：

```bash
curl -s http://localhost:4000/metrics | grep im_packet_error
```

---

## 日志解析

### 生产白名单 event（warning/error）

```
packet_decode_error storage_failed push_failed cluster_dispatch_failed
handler_crash internal_error packet_error auth_failed rate_limited
channel_subscribe_denied channel_publish_dropped channel_push_failed
```

`auth_failed` / `rate_limited` 有 **采样**，grep 可能漏条。

### grep 示例

```bash
# 单 trace
kubectl -n im-dev logs deployment/im --since=1h | grep 'trace_id":"YOUR-UUID"'

# 租户 + 事件
kubectl -n im-dev logs deployment/im --since=30m | grep '"app_key":"app_demo"' | grep packet_error

# 某 cmd 相关错误
kubectl -n im-dev logs deployment/im --since=30m | grep '"ref_cmd":"CMD_MSG_SEND"'
```

### jq（本机有 jq 时）

```bash
kubectl -n im-dev logs deployment/im --since=30m \
  | jq -c 'select(.trace_id=="YOUR-UUID")'
```

---

## 冒烟复现

```bash
mise run release-smoke-messaging
mise run release-smoke-auth

# 或直接 exec
kubectl -n im-dev exec deployment/im -- /app/bin/smoke-messaging
kubectl -n im-dev exec deployment/im -- /app/bin/smoke-auth
```

---

## 依赖栈 Pod

```bash
kubectl -n im-dev exec -it redis-0 -- redis-cli PING
kubectl -n im-dev exec -it postgres-0 -- psql -U im -d im_dev -c 'SELECT 1'
kubectl -n im-dev logs deployment/redpanda --since=10m
```

Kafka 旁路验证见 [deploy-guide.md](../../../docs/implementation/elixir/deploy-guide.md) §Event Bus。

---

## 引号陷阱

| 写法 | 结果 |
| --- | --- |
| `rpc 'IO.inspect("ok")'` | ✅ |
| `rpc "IO.inspect('ok')"` | ❌ shell 与 Elixir 引号冲突 |
| `rpc 'IM.Foo.bar(\"a\")'` | ✅ 字符串需转义 |

复杂表达式写入 heredoc 再 `rpc "$(cat <<'EOF' ... EOF)"` 更易维护。

---

## 相关文档

- [k8s/README.md](../../../deploy/elixir/im/k8s/README.md)
- [release-deploy-test.md](../../../docs/implementation/elixir/release-deploy-test.md)
- [release-smoke-messaging.md](../../../docs/implementation/elixir/release-smoke-messaging.md)
- [observability.md](../../../docs/design/observability.md)
