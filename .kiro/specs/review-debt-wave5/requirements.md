# Requirements — Review Debt Wave5

## 目标

补齐出站同带 coalesce，以及权限缓存对账与可观测性。

## 需求

### R1 Outbound coalesce

WHEN 出站队列深度 > `outbound_coalesce_depth`（默认 32），THE SYSTEM SHALL 在 drain 前将同带连续 `CMD_MSG_PUSH` 合并为 `CMD_MSG_PUSH_BATCH`（≤ `push_batch_max`）。

### R2 权限对账

THE SYSTEM SHALL 提供低频 Oban Worker，抽样比对 PG 与 L2 Cache，修复漂移并上报 `im_permission_cache_drift_total`。

### R3 权限 Telemetry

THE SYSTEM SHALL 上报 `im_permission_check_total{type,result,layer}`（layer=l1|l2|pg）。

### 非目标

改 proto；完整全量对账扫表。
