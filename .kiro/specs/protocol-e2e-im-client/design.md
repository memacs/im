# Design: im_client 协议 E2E

## 布局

- `apps/elixir/im/test/support/client_protocol_case.ex` — Sandbox shared + 连接辅助
- `apps/elixir/im/test/im_client/protocol/*.exs` — 分模块 E2E（19 用例）
- `apps/elixir/im` 测试依赖 `{:im_client, path: "../im_client", only: :test}`
- `config/test.exs`：`server: true` + 按 `MIX_TEST_PARTITION` 偏移端口

## 测试策略

| 模块 | 覆盖 CMD / REST |
|------|----------------|
| connection | sessions、AUTH、心跳、logout、/metrics |
| private_message | SEND/PUSH/ACK、批量 ACK、REST 双通道、幂等 |
| offline | OFFLINE_PULL |
| friend | 好友全链路 + 请求列表 |
| group / room | 管理 + 消息 |
| extensions | 已读/撤回/编辑/透传 |
| channel | 订阅/内部 publish/客户端 publish |

## 修复项（E2E 暴露）

- `IMWeb.PacketTransport` WebSock 出站帧格式 `{:binary, data}`
- `IM.Client.Transport` 移除 `name: nil`（WebSockex 冲突）
- REST `POST /messages` 补 `MsgSend.push_to_recipients/3`
- `Ecto.Adapters.SQL.Sandbox.mode({:shared, owner})` 供 Bandit 进程
