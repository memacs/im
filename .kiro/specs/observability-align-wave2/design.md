# Design — Observability Align Wave2

## 事件

| Telemetry 事件 | Prometheus 名 | 测量 |
|----------------|---------------|------|
| `[:im, :packet, :received]` | `im_packet_received_total` / bytes | count, bytes |
| `[:im, :packet, :sent]` | `im_packet_sent_total` / bytes | count, bytes |
| `[:im, :packet, :error]` | `im_packet_errors_total` | count |
| `[:im, :handler, :stop]` | `im_handler_duration_ms` | duration |
| `[:im, :ack, :latency]` | `im_ack_latency_ms` | duration + stage |
| `[:im, :connection, :opened]` | `im_connections_total` | count |
| `[:im, :auth, :result]` | `im_auth_total` | count + result |
| `[:im, :outbound, :dropped]` | `im_outbound_dropped_total` | count |

共享标签经 `IM.Telemetry.Tags`。
