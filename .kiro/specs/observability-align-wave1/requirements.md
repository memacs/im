# Requirements — Observability Align Wave1（日志契约）

## 目标

按 `docs/design/observability.md` §2.6 对齐 `IM.Log`：宏调用点、生产白名单、高频采样，并在关键失败路径接线。

## 需求

1. `IM.Log.warning/error/info/debug` **必须是宏**，经 `__CALLER__` 注入 `caller_module` / `caller_file` / `caller_line`。
2. 生产（`:im, :env == :prod`）仅允许设计 §2.6.2 白名单 event；`auth_failed` / `rate_limited` 经 `IM.Log.RateLimit` 每 key 每分钟最多一条。
3. `message` 字段等于 `event` 字符串；载荷走 Logger metadata（keyword）。
4. Handler：请求入口设置 metadata（trace/cmd/连接上下文）；`CMD_ERROR` 路径打 `packet_error`。
5. Auth 失败打 `auth_failed`；解码失败打 `packet_decode_error`；Channel 上行限流丢弃打 `channel_publish_dropped`（采样走 rate_limited 桶或独立）。
6. Hooks 异常改打白名单 `internal_error`（不再用未登记的 `hook_failed`）。
7. `config :im, :env, config_env()`。

### 非目标

- 引入 `logger_json` hex（需另批依赖确认）
- 完整 Prometheus 指标重命名（Wave2）
- `IM.Audit` 落库
