# Design

- Kafka：`EventBus.Kafka` → Buffer → `Producer.Memory`（测试）/ 后续 brod
- BlockCache：键 `im:block:{app}:{blocker}:{blocked}` 经 `IM.Cache`
- Internal：薄 Controller → Kick / DeviceBan / Message
- Compression：`IM.Protocol.Compression` + Codec
- Mute：`GroupStore.set_muted_until` + Message.validate_group
