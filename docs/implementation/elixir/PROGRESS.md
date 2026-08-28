# IM 实施进度

本文件为 **活文档**：每完成一项任务必须更新状态。AI 自主开发时 **每轮会话开始先读此文件**，结束时更新对应行。

> **IM 服务端**任务定义与验收标准见 [`roadmap.md`](roadmap.md)。  
> **im_client**（`apps/elixir/im_client`）设计见 [`test-client.md`](../../design/test-client.md)、实现见 [`test-client.md`](test-client.md)（elixir）。  
> **loadtest**（`apps/elixir/loadtest`）设计见 [`test-client.md`](../../design/test-client.md) §6、部署见 [`deploy/elixir/loadtest/`](../../../deploy/elixir/loadtest/)。  
> **im-console**（`apps/web/im-console`）设计见 [`web-console.md`](../../design/web-console.md)、实现见 [`web-console.md`](../web/web-console.md)。

**图例**：`pending` | `in_progress` | `done` | `blocked` | `deferred`

**当前阶段**：Phase 0–13 完成｜差距审查 [gap-review.md](gap-review.md) + [wave3 生产就绪](gap-review-wave3.md)

---

## 汇总

### IM 服务端（`apps/elixir/im`）

| Phase | 名称 | 进度 |
| --- | --- | --- |
| 0 | 工程脚手架 | 10 / 10 |
| 1 | 协议适配层 | 5 / 5 |
| 2 | WebSocket 与连接生命周期 | 14 / 14 |
| 3 | 单聊消息主路径 | 12 / 12 |
| 4 | 离线同步与收件箱 | 5 / 5 |
| 5 | 群聊与扇出 | 12 / 12 |
| 6 | 聊天室 PubSub | 6 / 6 |
| 7 | ACK 批量 / 已读 / 撤回 / 编辑 / 阅后即焚 / 透传 / 流式 / TTL 清理 | 10 / 10 |
| 8 | 群组、聊天室与好友管理 | 10 / 10 |
| 9 | 集群、旁路与可观测性 | 9 / 9 |
| 10 | 压测与上线准备 | 5 / 5（万连达标为环境实测） |
| 11 | 应用通道（App Channel） | 5 / 5（10 万订阅为环境实测） |
| 12 | Web 演示控制台 | 16 / 16 |
| 13 | 缓存、未读与会话（Remediation） | 12 / 12 |

### im_client 共享库（`apps/elixir/im_client`）

| Phase | 名称 | 进度 | 对齐 IM |
| --- | --- | --- | --- |
| C0 | 项目骨架与 Codec | 2 / 2 | P0-01、P1 |
| C1 | 连接与鉴权 MVP | 6 / 6 | P2 |
| C2 | 消息与双通道 | 4 / 4 | P3 |
| C3 | 离线 / 群 / 室 | 3 / 3 | P4–P6 |
| C4 | 扩展与管理命令 | 3 / 3 | P7–P8 |
| C5 | App Channel | 1 / 1 | P11 |

> **原则**：`im_client` 为共享库，**不打进 IM Release**；`loadtest` 仅 `path:` 依赖 `im_client`，不依赖 `im`。Codec 与 `im` 侧语义一致，随服务端 Phase **增量**交付命令封装。

### loadtest 压测服务（`apps/elixir/loadtest`）

| Phase | 名称 | 进度 | 对齐 IM |
| --- | --- | --- | --- |
| L0 | 项目骨架与编排 | 5 / 5 | P9、IC-04 |
| L1 | 连接与消息压测 | 3 / 3 | P10-01、P10-02 |
| L2 | 部署与工具链 | 3 / 3 | P10、deploy |
| L3 | 群 / 室 / Channel 扇出 | 3 / 3（规模达标需环境实测） | P5–P6、P11-05 |
| L4 | 报告与稳定性 | 2 / 2（72h 为环境跑法文档） | P10-04、P10-05 |
| L5 | 未读热路径压测 | 1 / 1 | LT-33 |

> **原则**：`loadtest` 为 **独立 Mix 项目 + Release**，与 IM Deployment 分离；K8s 以 **Job/CronJob** 对集群内 `svc/im` 施压。场景编排在 `loadtest`，单连接协议行为复用 `im_client`（`IM.Client`）。

---

## Phase 0：工程脚手架

> **验收口径**：标 `done` 必须是 **可验证** 的（`mix test` 绿 / `docker build` 绿 / `kubectl rollout status` 绿），
> 不以「文件已就位」为准。

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| P0-01 | 创建 mix 项目骨架 | done | Phoenix 1.8 + Ecto + Bandit；`config/runtime.exs`、`mix.lock`、`releases` 齐备 |
| P0-02 | mise.toml 与 proto-check | done | 见根目录 mise.toml |
| P0-03 | deploy/elixir/im/Dockerfile Release 构建 | done | `docker build` 通过；runtime 基础镜像改 trixie 以匹配 ERTS glibc |
| P0-04 | protobuf 代码生成集成 | done | `{:protobuf, "~> 0.14"}`；`mise run proto-gen` → `lib/pb/`（`Pb.Im.Protocol.*`）；生成物入库，CI 用 `proto-gen-check` 防漂移 |
| P0-05 | 目录结构骨架（`project-structure.md`） | done | 分层占位模块齐备，`mix compile --warnings-as-errors` 通过；契约测试见 `test/im/skeleton_test.exs` |
| P0-06 | ExUnit 与 CI 测试入口 | done | GHA Elixir job 含 postgres service + 依赖缓存；`mise run ci` 通过 |
| P0-07 | README 本地开发说明 | done | 根 README 含 mise、proto、Release+K8s 路径 |
| P0-08 | deploy/elixir/im/k8s/base 依赖栈 | done | redis + postgres 均为 StatefulSet + PVC；见下「加固」 |
| P0-09 | deploy/elixir/im/k8s/im + overlays/local | done | `kubectl rollout status deployment/im` 通过；探针拆 `/health/live` 与 `/health/ready` |
| P0-10 | release-deploy-local 脚本与文档 | done | release-deploy-test.md |

**健康检查与迁移**（P0-01 / P0-09 附带交付）：

| 能力 | 落位 | 验证 |
| --- | --- | --- |
| 存活探针 `/health/live` | `IMWeb.HealthController.live/2` | 200，不查库 |
| 就绪探针 `/health/ready` | `IMWeb.HealthController.ready/2` + `IM.Health.RepoChecker` | 200 `database: connected`；DB 异常 503 |
| 兼容入口 `/health` | 同 live | `mise run release-smoke` |
| Release 迁移 | `IM.Release.migrate/0` + `rel/overlays/bin/migrate` | 容器内 `bin/migrate` 退出码 0（只读根文件系统下亦可） |

**部署与 CI 加固**（Phase 0 收尾附带交付，基准见 `.agents/skills/kubernetes-skill`）：

| 项 | 落位 | 验证 |
| --- | --- | --- |
| PSS restricted | `k8s/base/namespace.yaml` 三个 `pod-security.kubernetes.io/*` 标签 | 全部 Pod 在 enforce 下 Running |
| 工作负载安全上下文 | `runAsNonRoot`+`runAsUser: 65534`、`drop: [ALL]`、`readOnlyRootFilesystem`、`seccompProfile` | 容器内 `touch /app` 失败、`id` = nobody |
| 只读根 + Release 临时目录 | `RELEASE_TMP=/tmp` + `emptyDir` | `bin/im start`、`bin/migrate` 均正常 |
| 优雅停机 | `terminationGracePeriodSeconds: 60` + `preStop sleep 5` + `maxUnavailable: 0` | 滚动更新先起新 Pod 再摘旧 Pod |
| 密钥收敛 | `DATABASE_URL`/`SECRET_KEY_BASE`/`RELEASE_COOKIE` 移入 Secret `im-runtime` | ConfigMap 中不再含密码 |
| 长连接会话亲和 | `Service.sessionAffinity: ClientIP` | — |
| 依赖栈持久化 | postgres/redis 改 StatefulSet + `volumeClaimTemplates`；Redis 开 AOF | PVC Bound；重启不丢序列号 |
| CI 严格化 | `--warnings-as-errors`、`mix hex.audit`、`proto-gen-check`、`docker build` job | `mise run ci` 通过 |

## Phase 1：协议适配层

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| P1-01 | IM.Protocol.Codec | done | ver=1 门禁；payload GZIP 协商（`Compression` + Auth）；见 protocol/*_test |
| P1-02 | IM.Protocol.Reply | done | ok/success/error；ErrorBody ref_cmd/ref_cid |
| P1-03 | IM.Protocol.Push | done | seq=0；PUSH / PUSH_BATCH |
| P1-04 | IM.Protocol.Router | done | Cmd 互转 + 可注入 handlers；未注册 → unknown_cmd |
| P1-05 | 错误码与 proto 一致 | done | `IM.Protocol.ErrorCodes`；AuthResp/KickNotify 烟雾 |

## Phase 2：WebSocket 与连接生命周期

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| P2-01 | 二进制 WebSocket Endpoint | done | `GET /ws` → `IMWeb.PacketTransport`（WebSock） |
| P2-02 | 连接状态机与未鉴权超时 | done | ConnectionState 三态；10s AUTH / 90s idle |
| P2-03 | CMD_AUTH_REQ / RESP | done | Commands.Auth；clear_local_data |
| P2-04 | Auth Service + Behaviour | done | `IM.Auth` + TokenVerifier；可 Mock |
| P2-05 | CMD_HEARTBEAT | done | Commands.Heartbeat + idle 重置 |
| P2-06 | CMD_KICK | done | Services.Kick → `{:im_kick, packet}` |
| P2-07 | 本节点连接 Registry | done | DeviceRegistry + UserRegistry |
| P2-07b | 按平台在线设备数限制 | done | DeviceLimit reject / kick_oldest |
| P2-08 | WebSocket 上下行计数/包大小/耗时 + host/msg_type 标签 | done | `im_packet_*` + Tags；见 observability-align-wave2 |
| P2-09 | 结构化日志 IM.Log | done | 宏+白名单+RateLimit+接线；见 observability-align-wave1 |
| P2-10 | Application.Dispatch 统一分发 | done | Channel/mute/internal 经 Dispatch；MessageContext.source 接线 |
| P2-11 | REST :api pipeline + Bearer | done | TraceId / Bearer / Fallback |
| P2-12 | HTTP sessions + access_tokens migration | done | users/user_devices/access_tokens |
| P2-13 | 封禁/踢人/clear_local_data | done | DeviceBan + local-data-cleared ACK |

## Phase 3：单聊消息主路径

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| P3-01 | MsgSendReq 单聊校验 | done | CHAT_PRIVATE + conv_id=`p:{lo}:{hi}` |
| P3-02 | 消息幂等 (app_key, from, client_msg_id) | done | 唯一索引 + 重复返回同 msg_id |
| P3-03 | Packet.cid 网关去重 | done | `IM.Gateway.CidDedup` ETS 5min |
| P3-04 | ChatMessage 落库 | done | message_bodies + user_inbox |
| P3-05 | ACK SERVER_RECEIVED + PUSH | done | Commands.MsgSend + Delivery.Router |
| P3-06 | 发送方其他设备 PUSH | done | exclude_device_id |
| P3-07 | ACK CLIENT_RECEIVED | done | Commands.MsgAck → 发送方设备 |
| P3-08 | 同步 Pre-Hooks | done | `IM.Hooks.PreSend` 默认 Noop |
| P3-09 | `conv_seq` 与 `priority` 分离；出站 WFQ + 老化 | done | `OutboundQueue`：WFQ+aging+burst+coalesce（深度>32 合并 PUSH_BATCH） |
| P3-10 | ACK 阶段延迟 histogram | done | `im_ack_latency_ms{stage}`；已有 send_to_server_ack / send_to_push |
| P3-11 | REST POST /api/v1/messages 双通道 | done | Dispatch + MessageController；70 tests |
| P3-12 | IM.Services.MsgId Snowflake + PG 兜底 | done | Lease（Cache NX EX + `id_workers`）；失败/回拨 → PG 兜底 T=1 |

## Phase 4：离线同步与收件箱

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| P4-01 | CMD_OFFLINE_PULL 分页 | done | limit 默认 50 / 上限 200；Commands.OfflinePull |
| P4-02 | inbox_seq 全量游标 | done | MessageStore.list_by_inbox_seq |
| P4-03 | conv_seq 会话游标 | done | MessageStore.list_by_conv_seq |
| P4-04 | 重连 AUTH → OFFLINE_PULL 流程 | done | 鉴权后 Router 放行 CMD_OFFLINE_PULL_REQ |
| P4-05 | 写扩散分片键设计 | done | user_inbox PK `(app_key, user_id, msg_id)` |

## Phase 5：群聊与扇出

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| P5-01 | CHAT_GROUP 发消息 | done | conv_id=`g:{group_id}`；成员校验；MsgSend 多收件人推送 |
| P5-02 | 单聊/群聊：`message_bodies` + `user_inbox` 写扩散 | done | GroupStore + insert_with_inbox；OFFLINE_PULL JOIN；`POST /api/v1/groups` |
| P5-03 | Phoenix.Tracker 跨节点 | done | `IM.UserTracker`；AUTH track；Delivery 优先 Tracker pid |
| P5-04 | 推送预编码 Packet | done | MsgSend 群/单聊 `Push.build`+encode 一次，`push_binary` 复用 |
| P5-05 | 小群 Tracker 直推 | done | 写扩散后经 Tracker/Registry 直推（树状扇出见 P5-06） |
| P5-06 | 大群树状扇出 + 批次并行 | done | `IM.Cluster.GroupPusher`；branching=8、RPC 2s、慢节点隔离 |
| P5-07 | target_users 定向群消息 | done | inbox/推送仅目标∪发送方 |
| P5-08 | CMD_MSG_PUSH_BATCH | done | `FanoutBatcher.deliver_messages`；≤ push_batch_max |
| P5-09 | Delivery.Router 在线/离线分流 | done | 单聊 `push_binary` 无在线设备 → `MobilePush`；群 `GroupPusher`；见 [mobile-push.md](mobile-push.md) |
| P5-10 | 群 inbox `insert_all` 分批 + Redis 发号 | done | insert_all chunk=500；序号仍 PG（Redis→P9） |
| P5-11 | ACK 与写扩散解耦 Oban | done | `IM.Workers.GroupInboxFanout`；`Jobs.GroupInboxFanout.enqueue` → Oban（test `:inline`） |
| P5-12 | 大群读扩散 read_fanout | done | FanoutPolicy + insert_body_only + OFFLINE_PULL conv 直查 |

## Phase 6：聊天室 PubSub

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| P6-01 | ROOM_JOIN + PubSub subscribe | done | Commands.RoomJoin/Create；topic `room:{app}:{room}` |
| P6-02 | 聊天室 PubSub broadcast | done | `IM.Room.PubSub`；不走 GroupPusher |
| P6-03 | 排除发送设备规则 | done | PacketTransport `room_deliver?` |
| P6-04 | 聊天室不进离线主路径 | done | 默认 ephemeral；无 user_inbox |
| P6-05 | 仅 SERVER_RECEIVED 必达 | done | MsgSend ACK_DOWN only |
| P6-06 | target_users 定向聊天室 | done | broadcast meta.target_users 过滤 |

## Phase 7：扩展消息命令

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| P7-01 | 批量 ACK | done | `Message.ack_batch_up` + `Commands.MsgAckBatch` |
| P7-02 | CMD_MSG_READ | done | 已读置 unread=0；发送路径 `bump_unread` |
| P7-03 | 撤回 | done | `MessageRecall`；超窗拒绝 |
| P7-04 | 编辑 | done | `MessageEdit`；`edit_version` 递增 |
| P7-05 | CMD_PASSTHROUGH | done | `Passthrough` + PassthroughStore；persist 登录后 PUSH |
| P7-09 | 阅后即焚 burn_after_read + BURN_PUSH | done | `IM.Workers.MessageBurn`；`schedule_in` / 即时 Oban insert |
| P7-06 | Handler 目录与 §22 对齐 | done | msg_ack_batch/read/recall/edit/passthrough 各一模块 |
| P7-07 | 流式消息透传模式 | done | PASSTHROUGH start/chunk/end；`stream?` 路径 |
| P7-08 | 流式消息模式（MSG_STREAM 落库） | done | StreamManager + 每块落库；Offline 还原 msg_type；见 `.kiro/specs/p7-08-p8-09/` |
| P7-10 | 消息 TTL 清理 Oban Job | done | `IM.Workers.TtlPurge`；`TTL_PURGE_AUTO` 时 Cron；`run_once/1` 同步 |

## Phase 8：群组、聊天室与好友管理

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| P8-01 | CMD_GROUP_* 基础 | done | Create/Dismiss/Join/Leave/Kick/Invite + WS Commands.Group.* |
| P8-02 | CMD_GROUP_* 管理员与转让 | done | SetAdmin/RemoveAdmin/Transfer/Update；DB role 0/1/2↔proto 1/2/3 |
| P8-03 | CMD_ROOM_* 管理 | done | Dismiss/Kick/Update；与 PubSub 联动 |
| P8-04 | 成员变更 PUSH | done | 群 Delivery.Router 广播；室 RoomPubSub.broadcast |
| P8-05 | CMD_FRIEND_* 添加/接受/拒绝 | done | FriendStore + Friend.add/accept/reject；CMD 800–808 |
| P8-06 | CMD_FRIEND_* 删除/拉黑 | done | delete/block/unblock；CMD 809–816 |
| P8-07 | CMD_FRIEND_* 列表与备注 | done | set_remark/list/request_list；CMD 817–822 |
| P8-08 | 拉黑后发消息拦截 | done | `BlockCache` SET + L1 ETS + PubSub 失效；`Friend.check_send_permission` |
| P8-09 | 租户级「须为好友才能单聊」 | done | `app_configs.friend.require_friend_to_send`；默认 false；`Friend.check_send_permission` |
| P8-10 | 群成员禁言 | done | Mute/DeviceBan L1；`Reconciler` 抽样对账；`permission.check` / `cache_drift` 指标 |

## Phase 9：集群与可观测性

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| P9-01 | libcluster | done | `IM.Cluster` + Cluster.Supervisor；`CLUSTER_STRATEGY=kubernetes|epmd`；默认单节点 |
| P9-01b | deploy/elixir/im/k8s/im 多副本联调（OrbStack） | done | `overlays/cluster`、`im-headless`、`RELEASE_NODE_MODE=pod_ip`、`rel/env.sh.eex`、PDB |
| P9-02 | Redis 序列号与热数据 | done | `IM.Cache` + Redis/Memory；Sequence Cache 权威、PG 冷启动播种与回退 |
| P9-03 | Kafka 核心三 Topic 旁路（upstream/session/downstream） | done | Buffer→Memory/Brod；默认 **Protobuf**（`Encoder`）；见 `.kiro/specs/review-debt-wave1/` |
| P9-03b | 下行 aggregated + 心跳采样 | done | FanoutPolicy + Downstream 1 条；Session heartbeat `:sampled\|:all\|:off` |
| P9-03c | 离线设备写 im.push | done | `PushNotificationBatchEvent` PB；依赖 REST 注册的 push_token |
| P9-04 | 同步 Hook 机制 | done | `Hooks.Pipeline`；`on_exception: :fail_closed\|:fail_open`；可改写/拦截 |
| P9-05 | Telemetry 与 trace_id 日志 | done | Wave1–5：指标+宏日志+NDJSON+Audit+§2.6.4 失败路径日志 |
| P9-06 | route_key Message 分片 | done | `IM.Cluster.Router` phash2；MsgSend `erpc` 转发；`node_role` 可配 |

## Phase 10：压测与上线

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| P10-01 | 连接压测 | done | LT-10 `connection_load` + CLI；万连达标需目标环境实测（见 loadtest-report.md） |
| P10-02 | 消息 QPS / 扇出压测 | done | LT-11 基线；LT-30 真 `CHAT_GROUP`；规模达标需环境实测 |
| P10-03 | 部署指南 | done | `docs/implementation/elixir/deploy-guide.md` |
| P10-04 | 故障演练文档 | done | `fault-drill.md`（节点宕机 / Redis / PG） |
| P10-05 | protocol 全量回归 checklist | done | `protocol-regression-checklist.md` + im_client E2E |

## Phase 11：应用通道（App Channel）

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| P11-01 | `channel.proto` + common.cmd 900–906 | done | proto/pb 已齐；ErrorCode 6001–6003 |
| P11-02 | `IM.Services.Channel` 订阅/ACL/限速 | done | ACL + RateLimiter 1/s burst 2；超限 `:drop_silent` |
| P11-03 | PubSub 下行 + internal publish API | done | caller 格式/允许名单；internal ctx `source=:http_internal` |
| P11-04 | 上行 + `im.app_events` Kafka | done | `EventBus.AppEvents` → Kafka 管线（Memory Producer）；flag 关 |
| P11-05 | 10 万订阅压测 + 丢包指标 | done | LT-31 `channel_subscribe` 场景；万级达标需环境实测 |

---

## im_client 轨道

模块命名空间：`IM.Client.*`。放置于 `apps/elixir/im_client/lib/im_client/`。

### Phase C0：项目骨架与 Codec

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| IC-01 | 创建 `im_client` mix 项目 | done | `mix.exs`；`mise run im_client:test` |
| IC-02 | proto 生成 + `IM.Client.Protocol.Codec` | done | `proto-gen` rsync 至 `im_client/lib/pb`；Codec 测试对齐 |

### Phase C1：连接与鉴权 MVP

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| IC-03 | WebSocket 连接 + 状态机 | done | `Connection` + WebSockex Transport；FakeTransport 单测 |
| IC-04 | `authenticate` / `heartbeat` / `disconnect` | done | |
| IC-05 | `Inbox` + `IM.Client.Assertions` | done | `await` by seq/cmd |
| IC-06 | `im` 测试依赖 `{:im_client, path: ..., only: :test}` | done | `test/im_client/protocol/` 37 E2E；集群另 2 E2E（`CLUSTER_E2E=1 mix test.cluster`） |
| IC-07 | `release-smoke` AUTH 冒烟路径 | done | `docs/implementation/elixir/release-smoke-auth.md` |
| IC-08 | `IM.Client.REST` 登录（`POST /api/v1/sessions`） | done | Req；压测 Worker 使用 |

### Phase C2：消息与双通道

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| IC-10 | `send_message` + 同步 `ACK_DOWN(SERVER_RECEIVED)` | done | 最小封装；等同 seq 响应 |
| IC-11 | `assert_push` + `ack_client_received` | done | Assertions.assert_push；Connection.ack_client_received |
| IC-12 | `IM.Client.REST` 发消息 | done | `REST.send_message/3` |
| IC-13 | `IM.Client.Scenario` 双用户 helper | done | start_pair / connect_pair / authenticate_pair |

### Phase C3：离线 / 群 / 室

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| IC-14 | `offline_pull` 封装 | done | Connection.offline_pull |
| IC-15 | 群聊命令封装（发消息、join 等） | done | create_group / join / leave；群消息走 send_message |
| IC-16 | 聊天室命令封装（join、broadcast 收包） | done | create_room / join / leave |

### Phase C4：扩展与管理命令

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| IC-17 | 撤回 / 编辑 / 透传 / 阅后即焚命令封装 | done | recall / edit / passthrough；burn 经 send_message 字段 |
| IC-18 | 群 / 室 / 好友管理命令封装 | done | friend accept/reject/delete/block/unblock；group kick/invite/admin/dismiss；ack_batch/msg_read |
| IC-19 | mise `im_client:*` 任务 + CI job | done | mise + GHA `im_client` job |

### Phase C5：App Channel

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| IC-20 | Channel 订阅 / 收 `CMD_CHANNEL_PUSH` | done | `subscribe_channels/2`；PUSH 由连接 Inbox 接收 |

---

## Web 演示控制台（`apps/web/im-console`）

独立前端 SPA（TypeScript + Vite + React）。设计 [web-console.md](../../design/web-console.md) DD-037；**须覆盖 protocol 全部客户端能力**（见设计 §3.2）。

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| P12-01 | 创建 `apps/web/im-console` 项目骨架 | done | Vite + React + TS |
| P12-02 | proto → TS + Packet Codec（全 CmdType） | done | protobufjs 静态生成；Vitest round-trip |
| P12-03 | 登录页 + REST sessions | done | platform=web；device_id 持久化 |
| P12-04 | WS 生命周期：AUTH/心跳/重连/KICK/ERROR | done | ImSocket + Debug |
| P12-05 | 消息 SEND/PUSH/ACK（含 BATCH） | done | Chat ACK_UP + ACK_BATCH；Debug Packet |
| P12-06 | `mise run web:dev` + Coverage/Debug 骨架 | done | `web:dev/test/build` |
| P12-07 | 全 MsgType 发送 + 双通道发消息 | done | MsgType 选择器；WS/REST 切换 |
| P12-08 | OFFLINE_PULL / 重连 / 多端 | done | OFFLINE_PULL 按钮；断线自动重连 |
| P12-09 | 已读 / 未读 | done | CMD_MSG_READ |
| P12-10 | 撤回 / 编辑 / 阅后即焚 / 透传 | done | Chat 页操作 |
| P12-11 | 群消息 + 全部 CMD_GROUP_* | done | Groups 页（创建/join/leave/dismiss/发消息） |
| P12-12 | 聊天室 + 全部 CMD_ROOM_* | done | Rooms 页 |
| P12-13 | 全部 CMD_FRIEND_* | done | Friends 页 |
| P12-14 | 全部 CMD_CHANNEL_* | done | Channel 页 + 收 PUSH |
| P12-15 | 各域 REST 与 WS 并列（dual-channel） | done | 服务端 REST §3.1 齐；Console 消息/群/通道切换 |
| P12-16 | Coverage 全绿验收 | done | 可演示；含会话 REST/未读 |

---

## Phase 13：缓存、未读与会话（Remediation）

> 差距审查：[gap-review.md](gap-review.md)

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| P13-01 | `IM.Conversation.UnreadCache` 热路径 | done | Redis/Memory INCR + dirty |
| P13-02 | `UnreadFlush` Oban 刷库 | done | `UNREAD_FLUSH_AUTO` |
| P13-03 | `GET /api/v1/conversations` | done | `ConversationController` |
| P13-04 | 群 `MemberCache` / `MetaCache` | done | 写穿/失效 |
| P13-05 | 聊天室 `MemberCache` / `MetaCache` | done | 与群对称 |
| P13-06 | `FriendshipCache` | done | `friends?` 热路径 |
| P13-07 | `ClientMsgIdCache` / `TokenCache` | done | 幂等 + 短 TTL |
| P13-08 | `AppConfig.Invalidator` 跨节点 | done | PubSub ETS |
| P13-09 | `POST /internal/v1/users/:id/provision` | done | 压测/运维 bootstrap |
| P13-10 | Release 冒烟 + CronJob | done | messaging + auth |
| P13-11 | Reconciler 群成员/好友 | done | `group_member` / `friendship` |
| P13-12 | 差距文档 + README 同步 | done | 本文 + gap-review |

---

## loadtest 轨道（续）

模块命名空间：`IM.LoadTest.*`。放置于 `apps/elixir/loadtest/lib/loadtest/`。依赖 `{:im_client, path: "../im_client"}`，**不得**依赖 `im`。

### Phase L0：项目骨架与编排

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| LT-01 | 创建 `loadtest` mix 项目 | done | `mix.exs` + Application |
| LT-02 | `path:` 依赖 `im_client` | done | 无 `:im` 依赖 |
| LT-03 | `IM.LoadTest.Worker` 虚拟用户 | done | REST + WS AUTH + send |
| LT-04 | `IM.LoadTest.Controller` 场景编排 | done | Task.async_stream 池 |
| LT-05 | `IM.LoadTest.Metrics` + `Reporter` | done | ETS + JSON 分位数 |

### Phase L1：连接与消息压测

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| LT-10 | `connection_load` 场景 | done | 对应 **P10-01**；规模达标见报告归档 |
| LT-11 | `message_flood` 场景 | done | **P10-02** 单聊基线 |
| LT-12 | `mix run` / CLI 入口 | done | `mix loadtest.run`；`mise run loadtest:run` |

### Phase L2：部署与工具链

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| LT-20 | `deploy/elixir/loadtest/Dockerfile` + Release | done | 独立镜像 + `bin/run_loadtest` |
| LT-21 | `deploy/elixir/loadtest/k8s/job.yaml` | done | 对 `svc/im` 跑 Job |
| LT-22 | mise `loadtest:*` 任务 + CI job | done | mise + GHA `loadtest` job |

### Phase L3：群 / 室 / Channel 扇出

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| LT-30 | `group_fanout` 大群扇出场景 | done | 真 `CHAT_GROUP` SEND；5000 人群达标需环境实测 |
| LT-31 | `channel_subscribe` 10 万订阅场景 | done | 场景+CLI；10 万达标需环境实测 |
| LT-32 | `room_broadcast` 聊天室广播场景 | done | 建室→JOIN→`CHAT_ROOM` SEND |

### Phase L4：报告与稳定性

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| LT-40 | 长时间稳定性脚本（如 72h） | done | `loadtest-stability.md` + `scripts/loadtest-soak.sh` |
| LT-41 | 压测报告模板 + checklist 挂钩 | done | loadtest-report.md + protocol-regression-checklist.md |

### Phase L5：未读热路径

| ID | 任务 | 状态 | 备注 |
| --- | --- | --- | --- |
| LT-33 | `unread_bump` 场景 | done | bump + conv_list + mark_read；`UserBootstrap`；K8s Job |
