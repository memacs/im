# Requirements — Observability Align Wave5（失败路径日志）

## 目标

补齐 DD-028 §2.6.4 剩余白名单 event 接线与 REST 链路上下文。

## 需求

1. REST pipeline 注入 `IM.Log.put_context`（`LogContext` Plug）。
2. `storage_failed` / `push_failed` / `cluster_dispatch_failed` / `rate_limited` / `channel_subscribe_denied` / `handler_crash` 接线。
3. WS 断连与 HTTP 登出写 `IM.Audit` `:auth_logout` + Kafka session logout。
