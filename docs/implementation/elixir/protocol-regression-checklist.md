# Protocol 主路径回归 Checklist（P10-05）

> 依据 `proto/` + `docs/design/protocol/protocol.md`。勾选表示**服务端已实现且有 ExUnit / 手工验证**。  
> Console / im_client 全覆盖另见各自轨道。

## 连接与会话

- [x] HTTP `POST /api/v1/sessions` 登录
- [x] WS `/ws` 升级 + `CMD_AUTH_REQ/RESP`
- [x] `CMD_HEARTBEAT_REQ/RESP`
- [x] 未鉴权非法命令关闭 / 鉴权超时
- [x] 踢人 / 设备限制（Phase 2）
- [x] 连接中 token 过期 `CMD_KICK(token_expired)`
- [x] `DELETE /api/v1/sessions/current`

## 单聊消息

- [x] `CMD_MSG_SEND` → 同步 `CMD_MSG_ACK_DOWN`
- [x] `CMD_MSG_PUSH` 下行
- [x] 客户端 ACK / 批量 ACK
- [x] REST 发消息（双通道）
- [x] 幂等 `cid`

## 离线

- [x] `CMD_OFFLINE_PULL`（及游标）

## 群 / 室

- [x] 群消息写扩散 + 扇出
- [x] 聊天室 join / 广播
- [x] 群管理 CMD（创建/解散/成员/管理员/转让等）
- [x] 室管理（解散/踢人/更新）

## 扩展

- [x] 已读 / 撤回 / 编辑
- [x] 群管理员撤回他人消息（recall.md §2）
- [x] 透传 / 流式透传
- [x] TTL / 阅后即焚
- [x] `MSG_STREAM` 落库（P7-08）

## 好友

- [x] 好友申请 / 同意 / 拒绝 / 删除 / 拉黑 / 备注
- [x] 须为好友才能单聊（P8-09，租户配置默认关）

## 集群与旁路

- [x] Telemetry `/metrics`
- [x] Sequence Cache（Memory/Redis + PG 回退）
- [x] libcluster + route_key 转发
- [x] Hook Pipeline fail-open/closed
- [x] EventBus Buffer MVP（Kafka Producer 默认关闭；`overlays/kafka-event-bus` 按需开启）

## 应用通道

- [x] `CMD_CHANNEL_*` 订阅 / 取消 / 上行 / PUSH（Phase 11）
- [x] `POST /internal/v1/channels/:ns/:name/publish`
- [ ] 10 万订阅环境实测报告

## 压测工具

- [x] `im_client` Codec + Connection AUTH
- [x] `im_client` 协议 E2E（`test/im_client/protocol/`，37 用例，随 `mise run test`）
- [x] E2E 上下行消息时序文档（[`protocol-e2e-message-sequences.md`](protocol-e2e-message-sequences.md) + [`protocol-e2e-traces.json`](protocol-e2e-traces.json)，`TRACE_EXPORT=1` 生成）
- [x] libcluster 跨节点 E2E（`test/im_client/protocol/cluster_test.exs`，2 用例 + peer boot 冒烟；需 `CLUSTER_E2E=1 PGPORT=15432 mix test.cluster`）
- [x] `loadtest` connection_load / message_flood CLI
- [ ] 单节点 3–5 万连接达标报告（环境相关，见 [`loadtest-report.md`](loadtest-report.md)）
- [ ] 大群扇出 P99&lt;200ms（LT-30）
