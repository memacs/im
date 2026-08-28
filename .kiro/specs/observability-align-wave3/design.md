# Design — Observability Align Wave3

## NDJSON

`IM.Log.JsonFormatter` 作为 `:default_handler` formatter（仅 prod）。  
开发仍用文本 formatter + 扩展 metadata 键。

## Telemetry 模块

| 模块 | 事件 |
|------|------|
| `IM.Telemetry.Storage` | `[:im, :storage, :stop]` |
| `IM.Telemetry.Delivery` | `[:im, :delivery, :stop]` + recipients |
| `IM.Telemetry.Message` | 扩展 ACK stages |
| `IM.Telemetry.Outbound` | depth / wait / aged |
| `IM.Telemetry.Cluster` | `[:im, :cluster, :dispatch]` |

## 测试

- JsonFormatter 单测：输出含 `@timestamp` 且 `message==event`
- Metrics 注册名出现在 `/metrics`
- MessageStore / Delivery / Heartbeat / MsgAck 路径不回归
