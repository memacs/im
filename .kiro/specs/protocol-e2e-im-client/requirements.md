# Requirements: im_client 协议 E2E

## 用户故事

- WHEN 开发者运行 `PGPORT=15432 mise run test`，THE SYSTEM SHALL 通过 `im_client` 对本地 IM 服务端执行协议主路径回归（连接/单聊/离线/群/室/好友/扩展/Channel）。
- WHEN 协议命令无同 seq 响应（ACK_UP、MSG_READ 等），THE SYSTEM SHALL 在 `IM.Client.Connection` 使用 `notify/3`  fire-and-forget 发送。

## 非目标

- 10 万 Channel 订阅压测、多节点 libcluster 转发（另见 loadtest / 环境报告）。
