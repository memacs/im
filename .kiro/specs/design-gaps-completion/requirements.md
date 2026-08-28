# Requirements: design gaps 收口

| Spec | `design-gaps-completion` |
| --- | --- |
| 覆盖 | Kafka Producer 管线、BlockCache、internal kick/ban/代发、payload GZIP、群禁言 |

## Acceptance

1. EventBus 可切换 `IM.EventBus.Kafka`：入 Buffer → Producer（Memory/可配）产出；测试可断言 produced。
2. `BlockCache` 热路径；block/unblock 写穿；`check_send_permission` 使用缓存。
3. `/internal/v1`：users/:id/kick、devices/:id/kick、devices/:id/ban、users/:id/messages。
4. Auth 协商压缩；Codec 支持 GZIP 解压/压缩；默认仍可 NONE。
5. 群成员 `muted_until` 生效时拒绝群发消息。
