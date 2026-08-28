# Requirements — Observability Align Wave3

## 目标

补齐 DD-028 剩余核心指标与生产 NDJSON 输出（不新增 `logger_json` hex，自研 Formatter）。

## 需求

1. 生产环境 stdout **单行 NDJSON**（信封：`@timestamp`/`level`/`event`/`message`/`service`/`host`/`node`）。
2. `im_storage_duration_ms`：MessageStore 写/读关键路径 span。
3. `im_delivery_duration_ms` + `im_push_recipients`：Delivery.Router 扇出。
4. ACK：`ack_up_processing`、`heartbeat_rtt`；`send_to_client_ack`（以正文 `server_time` 为起点近似）。
5. Outbound：`im_outbound_queue_depth`（按 band 采样）、`im_outbound_wait_ms`、`im_outbound_aged_total`。
6. `im_cross_node_dispatch_total`：跨节点 `send`/erpc 投递。

### 非目标

引入 `logger_json`；`IM.Audit` 落库；改 proto。
