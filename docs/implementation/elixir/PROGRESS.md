# IM 实施进度

本文件为 **活文档**：每完成一项任务必须更新状态。AI 自主开发时 **每轮会话开始先读此文件**，结束时更新对应行。

> **IM 服务端**任务定义与验收标准见 [`roadmap.md`](roadmap.md)。  
> **im_client**（`apps/elixir/im_client`）设计见 [`test-client.md`](../../design/test-client.md)、实现见 [`test-client.md`](test-client.md)（elixir）。  
> **loadtest**（`apps/elixir/loadtest`）设计见 [`test-client.md`](../../design/test-client.md) §6、部署见 [`deploy/elixir/loadtest/`](../../../deploy/elixir/loadtest/)。  
> **im-console**（`apps/web/im-console`）设计见 [`web-console.md`](../../design/web-console.md)、实现见 [`web-console.md`](../web/web-console.md)。

**图例**：`pending` | `in_progress` | `done` | `blocked` | `deferred`

**当前阶段**：IM Phase 0（进行中）｜im_client 未启动｜loadtest 未启动｜im-console 未启动

---

## 汇总

### IM 服务端（`apps/elixir/im`）

| Phase | 名称 | 进度 |
| --- | --- | --- |
| 0 | 工程脚手架 | 7 / 10 |
| 1 | 协议适配层 | 0 / 5 |
| 2 | WebSocket 与连接生命周期 | 0 / 14 |
| 3 | 单聊消息主路径 | 0 / 12 |
| 4 | 离线同步与收件箱 | 0 / 5 |
| 5 | 群聊与扇出 | 0 / 12 |
| 6 | 聊天室 PubSub | 0 / 6 |
| 7 | ACK 批量 / 已读 / 撤回 / 编辑 / 阅后即焚 / 透传 / 流式 | 0 / 8（1 deferred） |
| 8 | 群组、聊天室与好友管理 | 0 / 8（1 deferred） |
| 9 | 集群、旁路与可观测性 | 0 / 9 |
| 10 | 压测与上线准备 | 0 / 5 |
| 11 | 应用通道（App Channel） | 0 / 5 |
| 12 | Web 演示控制台 | 0 / 16 |

### im_client 共享库（`apps/elixir/im_client`）

| Phase | 名称 | 进度 | 对齐 IM |
| --- | --- | --- | --- |
| C0 | 项目骨架与 Codec | 0 / 2 | P0-01、P1 |
| C1 | 连接与鉴权 MVP | 0 / 6 | P2 |
| C2 | 消息与双通道 | 0 / 4 | P3 |
| C3 | 离线 / 群 / 室 | 0 / 3 | P4–P6 |
| C4 | 扩展与管理命令 | 0 / 3 | P7–P8 |
| C5 | App Channel | 0 / 1 | P11 |

> **原则**：`im_client` 为共享库，**不打进 IM Release**；`loadtest` 仅 `path:` 依赖 `im_client`，不依赖 `im`。Codec 与 `im` 侧语义一致，随服务端 Phase **增量**交付命令封装。

### loadtest 压测服务（`apps/elixir/loadtest`）

| Phase | 名称 | 进度 | 对齐 IM |
| --- | --- | --- | --- |
| L0 | 项目骨架与编排 | 0 / 5 | P9、IC-04 |
| L1 | 连接与消息压测 | 0 / 3 | P10-01、P10-02 |
| L2 | 部署与工具链 | 0 / 3 | P10、deploy |
| L3 | 群 / 室 / Channel 扇出 | 0 / 3 | P5–P6、P11-05 |
| L4 | 报告与稳定性 | 0 / 2 | P10-04、P10-05 |

> **原则**：`loadtest` 为 **独立 Mix 项目 + Release**，与 IM Deployment 分离；K8s 以 **Job/CronJob** 对集群内 `svc/im` 施压。场景编排在 `loadtest`，单连接协议行为复用 `im_client`（`IM.Client`）。

---

## Phase 0：工程脚手架

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| P0-01 | 创建 mix 项目骨架 | done | `apps/elixir/im/mix.exs`；`mix compile` 通过 |
| P0-02 | mise.toml 与 proto-check | done | 见根目录 mise.toml |
| P0-03 | deploy/elixir/im/Dockerfile Release 构建 | pending | Dockerfile 已就位；待 P0-01 后 `docker build` 验收 |
| P0-04 | protobuf 代码生成集成 | pending | |
| P0-05 | 目录结构骨架（`project-structure.md`） | pending | `apps/elixir/im/lib/` |
| P0-06 | ExUnit 与 CI 测试入口 | done | GHA Elixir job 已启用；`mise run ci` 通过 |
| P0-07 | README 本地开发说明 | done | 根 README 含 mise、proto、Release+K8s 路径 |
| P0-08 | deploy/elixir/im/k8s/base 依赖栈 | done | redis + postgres |
| P0-09 | deploy/elixir/im/k8s/im + overlays/local | done | K8s 清单已就位；待 P0-01 后 rollout 联调 |
| P0-10 | release-deploy-local 脚本与文档 | done | release-deploy-test.md |

## Phase 1：协议适配层

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| P1-01 | IM.Protocol.Codec | pending | 依赖 P0-04 |
| P1-02 | IM.Protocol.Reply | pending | |
| P1-03 | IM.Protocol.Push | pending | |
| P1-04 | IM.Protocol.Router | pending | |
| P1-05 | 错误码与 proto 一致 | pending | |

## Phase 2：WebSocket 与连接生命周期

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| P2-01 | 二进制 WebSocket Endpoint | pending | |
| P2-02 | 连接状态机与未鉴权超时 | pending | auth.md §7；已鉴权禁再 AUTH |
| P2-03 | CMD_AUTH_REQ / RESP | pending | 含 AuthResp.clear_local_data |
| P2-04 | Auth Service + Behaviour | pending | access_tokens 校验 |
| P2-05 | CMD_HEARTBEAT | pending | |
| P2-06 | CMD_KICK | pending | 含 KickNotify.clear_local_data |
| P2-07 | 本节点连接 Registry | pending | |
| P2-07b | 按平台在线设备数限制 | pending | auth.md §8；P2-03/P2-07 |
| P2-08 | WebSocket 上下行计数/包大小/耗时 + host/msg_type 标签 | pending | 见 observability.md |
| P2-09 | 结构化日志 IM.Log | pending | 生产 :warning；§2.6.0 统一 JSON；成功路径仅指标 |
| P2-10 | Application.Dispatch 统一分发 | pending | dual-channel-api.md |
| P2-11 | REST :api pipeline + Bearer | pending | 与 WS 共用 Dispatch |
| P2-12 | HTTP sessions + access_tokens migration | pending | design auth §9.2；auth-module.md |
| P2-13 | 封禁/踢人/clear_local_data | pending | design auth §9.6/§9.8 |

## Phase 3：单聊消息主路径

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| P3-01 | MsgSendReq 单聊校验 | pending | |
| P3-02 | 消息幂等 (app_key, from, client_msg_id) | pending | |
| P3-03 | Packet.cid 网关去重 | pending | |
| P3-04 | ChatMessage 落库 | pending | |
| P3-05 | ACK SERVER_RECEIVED + PUSH | pending | |
| P3-06 | 发送方其他设备 PUSH | pending | |
| P3-07 | ACK CLIENT_RECEIVED | pending | |
| P3-08 | 同步 Pre-Hooks | pending | |
| P3-09 | `conv_seq` 与 `priority` 分离；出站 WFQ + 老化 | pending | 见 message-send-ack.md §7 | |
| P3-10 | ACK 阶段延迟 histogram | pending | 见 observability.md |
| P3-11 | REST POST /api/v1/messages 双通道 | pending | 与 CMD_MSG_SEND 同 Service |
| P3-12 | IM.Services.MsgId Snowflake + PG 兜底 | pending | 见 msg-id-snowflake.md DD-039 |

## Phase 4：离线同步与收件箱

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| P4-01 | CMD_OFFLINE_PULL 分页 | pending | |
| P4-02 | inbox_seq 全量游标 | pending | |
| P4-03 | conv_seq 会话游标 | pending | |
| P4-04 | 重连 AUTH → OFFLINE_PULL 流程 | pending | |
| P4-05 | 写扩散分片键设计 | pending | |

## Phase 5：群聊与扇出

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| P5-01 | CHAT_GROUP 发消息 | pending | |
| P5-02 | 单聊/群聊：`message_bodies` + `user_inbox` 写扩散 | pending | 离线统一 JOIN 拉取 |
| P5-03 | Phoenix.Tracker 跨节点 | pending | |
| P5-04 | 推送预编码 Packet | pending | |
| P5-05 | 小群 Tracker 直推 | pending | |
| P5-06 | 大群树状扇出 + 批次并行 | pending | |
| P5-07 | target_users 定向群消息 | pending | |
| P5-08 | CMD_MSG_PUSH_BATCH | pending | |
| P5-09 | Delivery.Router 在线/离线分流 | pending | 见 mobile-push.md；Kafka 写入见 P9-03c |
| P5-10 | 群 inbox `insert_all` 分批 + Redis 发号 | pending | 见 group.md §6.1 |
| P5-11 | ACK 与写扩散解耦 Oban | pending | 见 group.md §6.2 |
| P5-12 | 大群读扩散 read_fanout | pending | group.md §6.3；`FanoutPolicy` + threshold 默认 500；Feature Flag 见 §6.3.1 |

## Phase 6：聊天室 PubSub

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| P6-01 | ROOM_JOIN + PubSub subscribe | pending | |
| P6-02 | 聊天室 PubSub broadcast | pending | |
| P6-03 | 排除发送设备规则 | pending | |
| P6-04 | 聊天室不进离线主路径 | pending | |
| P6-05 | 仅 SERVER_RECEIVED 必达 | pending | |
| P6-06 | target_users 定向聊天室 | pending | |

## Phase 7：扩展消息命令

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| P7-01 | 批量 ACK | pending | |
| P7-02 | CMD_MSG_READ | pending | |
| P7-03 | 撤回 | pending | |
| P7-04 | 编辑 | pending | |
| P7-05 | CMD_PASSTHROUGH | pending | |
| P7-09 | 阅后即焚 burn_after_read + BURN_PUSH | pending | burn-after-read.md；依赖 P7-02 |
| P7-06 | Handler 目录与 §22 对齐 | pending | |
| P7-07 | 流式消息透传模式 | pending | PASSTHROUGH + start/chunk/end；见 stream-message.md |
| P7-08 | 流式消息模式（MSG_STREAM 落库） | deferred | v1 不实现；MVP 透传已覆盖主场景；proto 保留 |

## Phase 8：群组、聊天室与好友管理

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| P8-01 | CMD_GROUP_* 基础 | pending | |
| P8-02 | CMD_GROUP_* 管理员与转让 | pending | |
| P8-03 | CMD_ROOM_* 管理 | pending | |
| P8-04 | 成员变更 PUSH | pending | |
| P8-05 | CMD_FRIEND_* 添加/接受/拒绝 | pending | CMD 800–808 |
| P8-06 | CMD_FRIEND_* 删除/拉黑 | pending | CMD 809–816 |
| P8-07 | CMD_FRIEND_* 列表与备注 | pending | CMD 817–822 |
| P8-08 | 拉黑后发消息拦截 | pending | 接入 CMD_MSG_SEND；friend.md §7.2 |
| P8-09 | 租户级「须为好友才能单聊」 | deferred | v1 默认关闭；待租户配置（Phase 9+） |

## Phase 9：集群与可观测性

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| P9-01 | libcluster | pending | |
| P9-01b | deploy/elixir/im/k8s/im 多副本联调（OrbStack） | pending | 依赖 P9-01、P0-08 |
| P9-02 | Redis 序列号与热数据 | pending | |
| P9-03 | Kafka 核心三 Topic 旁路（upstream/session/downstream） | pending | 五 Topic 见 kafka-event-bus.md；`im.push`→P9-03c、`im.app_events`→P11-04 |
| P9-03b | 下行 aggregated + 心跳采样 | pending | 大群/聊天室减量 |
| P9-03c | 离线设备写 im.push | pending | `PushNotificationBatchEvent`；见 mobile-push.md |
| P9-04 | 同步 Hook 机制 | pending | |
| P9-05 | Telemetry 与 trace_id 日志 | pending | 见 observability.md §2.6.0 JSON 输出 |
| P9-06 | route_key Message 分片 | pending | |

## Phase 10：压测与上线

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| P10-01 | 连接压测 | pending | 实现见 loadtest **LT-10** |
| P10-02 | 消息 QPS / 扇出压测 | pending | 实现见 loadtest **LT-11**、**LT-12** |
| P10-03 | 部署指南 | pending | |
| P10-04 | 故障演练文档 | pending | |
| P10-05 | protocol 全量回归 checklist | pending | |

## Phase 11：应用通道（App Channel）

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| P11-01 | `channel.proto` + common.cmd 900–906 | pending | 见 app-channel.md |
| P11-02 | `IM.Services.Channel` 订阅/ACL/限速 | pending | 1/s/连接；依赖 P2 |
| P11-03 | PubSub 下行 + internal publish API | pending | 依赖 P6 |
| P11-04 | 上行 + `im.app_events` Kafka | pending | 依赖 P9 EventBus |
| P11-05 | 10 万订阅压测 + 丢包指标 | pending | 实现见 loadtest **LT-31** |

---

## im_client 轨道

模块命名空间：`IM.Client.*`。放置于 `apps/elixir/im_client/lib/im_client/`。

### Phase C0：项目骨架与 Codec

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| IC-01 | 创建 `im_client` mix 项目 | pending | `apps/elixir/im_client/mix.exs`；`mix compile` 通过 |
| IC-02 | proto 生成 + `IM.Client.Protocol.Codec` | pending | 依赖 P1-01、IC-01；与 `im` codec 测试向量一致 |

### Phase C1：连接与鉴权 MVP

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| IC-03 | WebSocket 连接 + 状态机 | pending | `IM.Client.Connection`；依赖 P2-01、IC-02 |
| IC-04 | `authenticate` / `heartbeat` / `disconnect` | pending | 依赖 P2-03、P2-05、IC-03 |
| IC-05 | `Inbox` + `IM.Client.Assertions` | pending | 按 `seq`/`cmd` 等待 RESP/PUSH |
| IC-06 | `im` 测试依赖 `{:im_client, path: ...}` | pending | `test/support` 迁出 TestClient 占位 |
| IC-07 | `release-smoke` AUTH 冒烟路径 | pending | 依赖 IC-06、P0-10；K8s 部署后自动 AUTH |
| IC-08 | `IM.Client.REST` 登录（`POST /api/v1/sessions`） | pending | 依赖 P2-11、P2-12、IC-04 |

### Phase C2：消息与双通道

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| IC-10 | `send_message` + 同步 `ACK_DOWN(SERVER_RECEIVED)` | pending | 依赖 P3-05、IC-06 |
| IC-11 | `assert_push` + `ack_client_received` | pending | 双阶段 ACK；依赖 P3-07 |
| IC-12 | `IM.Client.REST` 发消息 | pending | 依赖 P3-11；与 WS 同场景对照 |
| IC-13 | `IM.Client.Scenario` 双用户 helper | pending | 单聊集成测试骨架 |

### Phase C3：离线 / 群 / 室

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| IC-14 | `offline_pull` 封装 | pending | 依赖 P4-01、IC-10 |
| IC-15 | 群聊命令封装（发消息、join 等） | pending | 依赖 P5-01、IC-10 |
| IC-16 | 聊天室命令封装（join、broadcast 收包） | pending | 依赖 P6-01、IC-10 |

### Phase C4：扩展与管理命令

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| IC-17 | 撤回 / 编辑 / 透传 / 阅后即焚命令封装 | pending | 依赖 P7-03–P7-05、P7-09 |
| IC-18 | 群 / 室 / 好友管理命令封装 | pending | 依赖 P8-01–P8-07 |
| IC-19 | mise `im_client:*` 任务 + CI job | pending | 变更 `apps/elixir/im_client/**` 时跑测 |

### Phase C5：App Channel

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| IC-20 | Channel 订阅 / 收 `CMD_CHANNEL_PUSH` | pending | 依赖 P11-02、IC-04 |

---

## Web 演示控制台（`apps/web/im-console`）

独立前端 SPA（TypeScript + Vite + React）。设计 [web-console.md](../../design/web-console.md) DD-037；**须覆盖 protocol 全部客户端能力**（见设计 §3.2）。

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| P12-01 | 创建 `apps/web/im-console` 项目骨架 | pending | Vite + React + TS |
| P12-02 | proto → TS + Packet Codec（全 CmdType） | pending | 与 `im` 测试向量一致 |
| P12-03 | 登录页 + REST sessions | pending | 依赖 IM P2-11/12 |
| P12-04 | WS 生命周期：AUTH/心跳/重连/KICK/ERROR | pending | 依赖 IM P2-03–05 |
| P12-05 | 消息 SEND/PUSH/ACK（含 BATCH） | pending | 依赖 IM P3-05+ |
| P12-06 | `mise run web:dev` + Coverage/Debug 骨架 | pending | 本地联调 |
| P12-07 | 全 MsgType 发送 + 双通道发消息 | pending | 依赖 IM P3 REST |
| P12-08 | OFFLINE_PULL / 重连 / 多端 | pending | 依赖 IM P4 |
| P12-09 | 已读 / 未读 | pending | 依赖 IM P7 |
| P12-10 | 撤回 / 编辑 / 阅后即焚 / 透传 | pending | 依赖 IM P7 |
| P12-11 | 群消息 + 全部 CMD_GROUP_* | pending | 依赖 IM P5–P8 |
| P12-12 | 聊天室 + 全部 CMD_ROOM_* | pending | 依赖 IM P6 |
| P12-13 | 全部 CMD_FRIEND_* | pending | 依赖 IM P8 |
| P12-14 | 全部 CMD_CHANNEL_* | pending | 依赖 IM P11 |
| P12-15 | 各域 REST 与 WS 并列（dual-channel） | pending | 贯穿 P3–P11 |
| P12-16 | Coverage 全绿验收 | pending | 设计 §3.2 已实现项均可演示 |

---

## loadtest 轨道

模块命名空间：`IM.LoadTest.*`。放置于 `apps/elixir/loadtest/lib/loadtest/`。依赖 `{:im_client, path: "../im_client"}`，**不得**依赖 `im`。

### Phase L0：项目骨架与编排

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| LT-01 | 创建 `loadtest` mix 项目 | pending | `apps/elixir/loadtest/mix.exs`；`mix compile` 通过 |
| LT-02 | `path:` 依赖 `im_client` | pending | 依赖 IC-04、LT-01 |
| LT-03 | `IM.LoadTest.Worker` 虚拟用户 | pending | 基于 `IM.Client` 建连、AUTH、发消息 |
| LT-04 | `IM.LoadTest.Controller` 场景编排 | pending | Worker 池、任务分发、超时汇总 |
| LT-05 | `IM.LoadTest.Metrics` + `Reporter` | pending | QPS、P50/P90/P99、错误码分布；JSON 报告 |

### Phase L1：连接与消息压测

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| LT-10 | `connection_load` 场景 | pending | 单节点 3–5 万连接目标；对应 **P10-01** |
| LT-11 | `message_flood` 场景 | pending | 单聊消息 QPS；对应 **P10-02** 基线 |
| LT-12 | `mix run` / CLI 入口 | pending | 本地与 CI 可一键跑 L1 场景 |

### Phase L2：部署与工具链

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| LT-20 | `deploy/elixir/loadtest/Dockerfile` + Release | pending | 构建上下文仓库根；独立镜像 |
| LT-21 | `deploy/elixir/loadtest/k8s/job.yaml` | pending | 对 `svc/im` 跑 Job；见 deploy README |
| LT-22 | mise `loadtest:*` 任务 + CI job | pending | 变更 `apps/elixir/loadtest/**` 时跑测 |

### Phase L3：群 / 室 / Channel 扇出

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| LT-30 | `group_fanout` 大群扇出场景 | pending | 5000 人群 P99 小于 200ms；**P10-02** |
| LT-31 | `channel_subscribe` 10 万订阅场景 | pending | 丢包率、P99；对应 **P11-05** |
| LT-32 | `room_broadcast` 聊天室广播场景 | pending | 依赖 P6-02、LT-03 |

### Phase L4：报告与稳定性

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| LT-40 | 长时间稳定性脚本（如 72h） | pending | 文档化运行方式；配合 **P10-04** |
| LT-41 | 压测报告模板 + checklist 挂钩 | pending | 与 **P10-05** protocol 回归清单对齐 |
