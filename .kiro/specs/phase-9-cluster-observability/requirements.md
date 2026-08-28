# Requirements: Phase 9 集群与可观测性

| Spec | `phase-9-cluster-observability` |
| Roadmap | P9-01 ~ P9-06 |

1. WHEN 多 Pod 部署启用 libcluster，THE SYSTEM SHALL 形成 Erlang 集群并使 UserTracker 跨节点可见。
2. WHEN 配置 `REDIS_URL`，THE SYSTEM SHALL 用 Redis 承担序列号/热路径；Redis 不可用时可回退 PG（可配置）。
3. WHEN Kafka 旁路启用，THE SYSTEM SHALL 异步写 upstream/session/downstream，且失败不阻塞 SEND。
4. THE SYSTEM SHALL 暴露 `GET /metrics`（Prometheus）并保留结构化日志 `trace_id`。
5. WHEN `IM_NODE_ROLE=message`，THE SYSTEM SHALL 按 `route_key` 一致性哈希路由（P9-06）。
