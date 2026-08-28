# Requirements — Observability Align Wave4

## 目标

补齐阅后即焚监控（burn-after-read §8）与鉴权审计异步落库（DD-028 / auth-module §8）。

## 需求

1. `im_msg_burn_scheduled_total` / `im_msg_burn_executed_total` / `im_msg_burn_lag_ms`。
2. `IM.Audit.record/2` 经 `Task.Supervisor` 异步写 `audit_logs`（仅 `created_at`）。
3. AUTH 成功/失败调用 Audit（不阻塞主路径）。
4. 审计与 stdout `IM.Log` 分离。

### 非目标

改 proto；暴力破解锁定；完整策略分布看板。
