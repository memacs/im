# Requirements：审查还债 Wave 2

## EARS

- WHEN 构建 REST/WS/internal 请求上下文，THE SYSTEM SHALL 填充 `source`、控制项与（internal）`caller_service`/`client_ip`。
- WHEN `write_kafka` 为 false，THE SYSTEM SHALL 不调用 EventBus 旁路。
- WHEN `run_hooks` 为 false，THE SYSTEM SHALL 跳过 PreSend。
- WHEN internal caller 非法或不在允许名单，THE SYSTEM SHALL 返回 400。
- WHEN 新消息落库成功，THE SYSTEM SHALL 对收件人（非发送方）递增 `conversations.unread_count`。
- WHEN WS Channel 命令执行，THE SYSTEM SHALL 经 `Dispatch`（pubsub: true）。
