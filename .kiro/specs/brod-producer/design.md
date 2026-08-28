# Design：brod Producer

```
EventBus.Kafka → Buffer → Producer.produce
                              ├─ Memory（默认/测试）
                              └─ Brod → :brod.produce_sync(client, topic, :hash, key, value)
```

- `IM.EventBus.Producer.Brod`：实现 Producer behaviour；`brod_adapter` 可注入测试假实现。
- `IM.EventBus.Producer.Brod.Client`：监督树内 `start_link_client`（`auto_start_producers: true`）。
- 配置：`event_bus_kafka` 的 `brokers` / `client_id`；runtime：`KAFKA_BROKERS`、`EVENT_BUS_PRODUCER=brod`、`EVENT_BUS_ENABLED=true`。
- partition key：优先 `msg_id` / `event_id` / `trace_id`。
