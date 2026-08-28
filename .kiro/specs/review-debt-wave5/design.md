# Design — Review Debt Wave5

## Coalesce

`OutboundQueue.drain/2` 入口：若 `depth > coalesce_depth`，对各带调用 `coalesce_band/1`：

1. 顺序扫描 item
2. 可解码为单条 `CMD_MSG_PUSH` 的进入缓冲
3. 缓冲按 `push_batch_max` 切块 → `Push.build(:CMD_MSG_PUSH_BATCH, …)` → 新 item
4. 不可解码（ACK/KICK/已是 BATCH）原样保留

## Reconciler

`IM.Permission.Reconciler.run(app_key, opts)` → `%{block: n, mute: n, device_ban: n}`  
Worker：`IM.Workers.PermissionReconcile`；Cron 由 `PERMISSION_RECONCILE_AUTO` 控制。

## Telemetry

`IM.Permission.Telemetry.emit_check(type, result, layer)`
