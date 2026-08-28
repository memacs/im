# Design: Phase 9

## 建议实施顺序

1. **P9-05** `/metrics` + Telemetry.Supervisor（依赖已半齐，解锁观测）
2. **P9-02** Sequence Redis 后端 + PG fallback
3. **P9-01** libcluster（DNS/Kubernetes 策略）+ P9-01b 多副本
4. **P9-04** Hook 失败策略可配置
5. **P9-03*** Kafka Broadway（旁路，可 feature flag）
6. **P9-06** Message 节点 route_key 哈希

## 已有底座

- UserTracker / SlowNode / GroupPusher
- Sequence（PG）/ Telemetry emit / PreSend / MobilePush 内存队列
- `route_key` 字段已填
