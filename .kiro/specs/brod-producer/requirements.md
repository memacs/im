# Requirements：真实 brod Producer

## User Story

作为运维/平台，我希望 IM 旁路事件在开启时写入真实 Kafka，以便下游消费审计与推送，而不阻塞 SEND ACK。

## EARS

- WHEN `event_bus_enabled=true` 且 `event_bus_producer=Brod` 且已配置 brokers，THE SYSTEM SHALL 经 brod `produce_sync` 将事件写入对应 Kafka topic。
- WHEN brokers 未配置或 produce 失败，THE SYSTEM SHALL 不崩溃 Buffer / 不阻塞调用方；记 telemetry。
- WHEN 未启用 Brod（默认 Memory），THE SYSTEM SHALL 不启动 brod client。
