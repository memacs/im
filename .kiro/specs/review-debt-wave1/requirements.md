# Requirements：审查还债 Wave 1

## User Stories

1. 作为多节点集群，我希望 `msg_id` worker 经租约分配，避免碰撞。
2. 作为下游消费者，我希望旁路事件为 `event.proto` Protobuf。
3. 作为移动端 SDK，我希望经 REST 注册 `push_token`。
4. 作为压测，我希望 LT-30/32 真正打群扇出与聊天室广播。

## EARS

- WHEN MsgId 启动，THE SYSTEM SHALL 从 0..1023 租约 `worker_id`（Cache NX + PG 镜像）；失败则 PG 兜底发号。
- WHEN EventBus 序列化为默认模式，THE SYSTEM SHALL 产出对应 `Pb.Im.Event.*` bytes。
- WHEN 客户端 `PUT /api/v1/devices/:id/push-token`，THE SYSTEM SHALL 更新 `user_devices.push_token`。
- WHEN 运行 group_fanout / room_broadcast，THE SYSTEM SHALL 使用群/室 SEND 路径（非私聊冒充）。
