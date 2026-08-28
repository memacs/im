# 故障演练预期行为（P10-04）

| 项 | 内容 |
| --- | --- |
| 状态 | 文档交付 |
| 范围 | 单节点 / 多副本 IM；Redis Sequence Cache；无 Kafka 强制依赖（默认 `event_bus_enabled: false`） |

---

## 1. IM 节点宕机

| 现象 | 预期 |
| --- | --- |
| Pod/进程被杀 | K8s 重启；`/health/live` 短暂失败 |
| 该节点上的 WS 连接 | 客户端断开；需重连 + AUTH +（按协议）离线拉取 |
| 他节点连接 | 不受影响（无粘性会话假设） |
| 消息持久化 | 已落库消息不丢；进行中的 SEND 可能收到超时/错误，客户端按 cid 重试 |
| 多副本 + Router | `route_key` 一致性哈希在成员变更后重分布；短时 `erpc` 失败应映射为可重试错误 |

**演练步骤（本地）**：`kubectl delete pod -n im -l app=im --wait=false`，观察新 Pod Ready，客户端重连后可发消息。

---

## 2. Redis 超时 / 不可用

| 组件 | 预期 |
| --- | --- |
| Sequence Cache（P9-02） | Redis 失败时回退 PostgreSQL 发号；延迟升高但主路径可用 |
| 会话 / 限流等（若仅用 PG） | 无额外影响 |
| 连接风暴 | 回退路径 DB 压力上升；应配合限流与扩容 |

**演练步骤**：对 Redis 注入 `NETWORK_UNAVAILABLE` 或缩容 Redis 副本为 0，发送单聊消息，确认仍返回 `ACK_DOWN`，日志出现 cache 回退。

---

## 3. Postgres 短暂不可用

| 现象 | 预期 |
| --- | --- |
| Ready 探针失败 | 流量摘除（若配置 readiness） |
| 写消息 / 登录 | 返回 5xx / `CMD_ERROR`；不静默丢包 |
| 恢复后 | 连接池恢复；无需全量重启（视超时配置） |

---

## 4. 压测侧故障

| 现象 | 预期 |
| --- | --- |
| Worker 超时 | Controller `on_timeout: :kill_task`，计入 failure；报告仍写出 |
| 目标 `svc/im` 不可达 | 登录/建连失败率升高；Job 非 0 退出（按脚本约定） |

---

## 5. 记录模板

```text
日期：
环境：local / staging
故障：节点宕机 | Redis | PG
操作：
观察（连接数、错误码、P99、是否丢消息）：
结论 / 后续：
```
