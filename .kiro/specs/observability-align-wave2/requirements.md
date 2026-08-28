# Requirements — Observability Align Wave2（指标对齐）

## 目标

按 `docs/design/observability.md` §2.3–2.5 对齐 Prometheus 指标命名、标签与关键埋点。

## 需求

1. 包计数/字节：`im_packet_received/sent_total` + bytes；标签 `cmd`（枚举名）、`direction=up|down`、`msg_type`、`host`、`node`。
2. `im_packet_errors_total`（`code`/`ref_cmd`/`host`）；Handler `CMD_ERROR` 路径埋点。
3. `im_handler_duration_ms`：标签含 `cmd`/`result`/`direction`/`msg_type`/`host`。
4. ACK：统一 `im_ack_latency_ms{stage=...}`（至少 `send_to_server_ack` / `send_to_push`）。
5. `im_connections_active` 保留；新增 `im_connections_total`、`im_auth_total{result}`。
6. 已有 `event_bus` / `channel.aggregate_drop` / `permission.*` / `mobile_push` 注册进 `/metrics`。
7. Outbound：`im_outbound_dropped_total`（enqueue 丢弃时）；深度可后续 Gauge。

### 非目标

完整 storage/delivery span；`logger_json`；全部 ACK stage（client_ack / heartbeat_rtt 可后续）。
