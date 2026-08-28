# IM 系统产品介绍

> 面向产品、业务方与技术决策者的能力概览。

**文档导航**：[文档总索引](README.md) · [功能对照表](module-map.md) · [架构总览](design/architecture-overview.md) · [HTTP API](implementation/elixir/http-api-reference.md) · [实施进度](implementation/elixir/PROGRESS.md)

---

## 一句话

这是一套面向 **百万在线、多租户** 场景设计的 **即时通讯后端**：用 **WebSocket + Protobuf** 做实时通道，用 **REST** 做同等能力的管理接口，覆盖 **单聊、群聊、聊天室、业务事件通道** 全场景，并内置 **离线补拉、多端同步、系统推送、Kafka 旁路** 等企业级能力。

---

## 为什么选择这套系统

### 对业务方

| 优势 | 说明 |
|------|------|
| **开箱即用 IM 能力** | 登录鉴权、发消息、收推送、离线拉取、已读/撤回/编辑/阅后即焚、好友与群组——无需从零造轮子 |
| **三种会话形态** | 单聊（持久化 + 离线）、群聊（小群直推 + 大群扇出）、聊天室（万人实时广播）各取所需 |
| **业务事件也能走 IM 长连接** | **应用通道（App Channel）**：后端向订阅者广播、客户端上报事件进 Kafka，不进聊天会话列表 |
| **双通道一致体验** | 同一套业务逻辑同时支持 **WebSocket 实时** 与 **REST API**，Web / 移动端 / 服务端均可对接 |
| **多租户隔离** | 按 `app_key` 隔离租户，适合 SaaS、多 App、多业务线共用一套 IM 集群 |

### 对技术团队

| 优势 | 说明 |
|------|------|
| **协议先行、文档完整** | Protobuf 定义 + 协议规范 + 30+ 专题设计文档；改协议有决策编号（DD-xxx）可追溯 |
| **主路径为性能而设计** | 发消息 **同步 ACK**（服务端已收到），Kafka / 审计 **异步旁路**，不拖慢聊天 |
| **水平扩展** | 多节点部署、跨节点找连接、大群树状扇出、聊天室/App Channel PubSub 广播 |
| **可观测、可运维** | Prometheus 指标 + 统一 JSON 日志（`trace_id` 全链路）；内部 API 支持踢人、封禁、代发 |
| **实现语言可换** | 协议与 `proto/` 语言无关；当前主推 **Elixir/OTP**，Java 实现路径已预留 |
| **部署与 CI 就绪** | Kubernetes 清单、mise 任务、GitHub Actions；本地 OrbStack 可跑与线上一致的 Release 验收 |

### 对 AI / 实时互动场景

| 优势 | 说明 |
|------|------|
| **流式消息** | 支持 AI 回复、长文本分段推送等流式场景 |
| **透传信令** | 打字状态、自定义实时信号，不进消息库、不污染会话 |
| **应用通道** | 订单状态、车队告警等业务事件：后端广播 + 客户端上报，统一 Kafka 出口 |

---

## 功能全景

### 连接与账号

- HTTP 登录获取 `access_token`，WebSocket 首包鉴权
- 心跳保活、断线重连与离线恢复
- **多端在线**：同一用户多设备同时在线，消息同步到各端
- 设备数限制、互踢、封禁；内部服务可踢人下线、可选清空客户端本地数据

### 消息与会话

- **单聊 / 群聊 / 聊天室** 发送与接收
- 双阶段 ACK：发送方先收到「服务端已收到」，再异步推送给对端
- **离线拉取**（单聊、群聊）：上线后按收件箱序号补消息
- **已读回执**、**未读数**、**消息撤回**、**消息编辑**、**阅后即焚**（单聊）
- **批量下行**（`PUSH_BATCH`）降低大包开销
- 出站 **优先级队列**（WFQ + aging）：ACK / 普通消息 / 低优先级互不饿死

### 社交与房间

- **好友**：申请、同意、拒绝、删除、拉黑、备注
- **群组**：建群、邀请、踢人、转让、群资料；大群扇出优化
- **聊天室**：加入/离开、万人级在线广播（默认不存离线历史）

### 应用通道（App Channel）

- 客户端 **订阅业务 Topic**，后端经 **Internal API** 向订阅者广播
- 客户端 **上报业务事件**（限速 1 条/秒），异步写入 Kafka `im.app_events`
- 尽力而为、允许丢、无离线补发——适合通知类、非会话类业务
- 支持 **共享 Topic 广播**（如车队告警）与 **私有 Channel 单点下发**（如 `personal:{user_id}`）

### 平台能力

- **系统推送**（APNs / FCM）：设备离线时手机通知栏提醒
- **Kafka 事件总线**（五 Topic）：上下行镜像、投递、推送任务、应用事件——供数仓/风控/BI 订阅
- **权限热缓存**：拉黑、禁言、封禁变更跨节点秒级生效
- **Payload 压缩协商**（gzip/zstd）：弱网场景降低带宽（见 [payload-compression](design/payload-compression.md)）
- **统一 trace_id**：从 HTTP/WS 入口贯穿 ACK、推送、Kafka、日志

---

## 典型使用场景

| 场景 | 推荐能力组合 |
|------|----------------|
| 社交 App 私聊 + 群聊 | 单聊 + 群聊 + 好友 + 已读/撤回 + 离线拉取 + 系统推送 |
| 直播 / 活动互动 | 聊天室 + 透传（点赞、礼物动效信令） |
| 客服 / 工单通知 | 单聊或应用通道 + REST 代发（Internal API） |
| 车队 / 物联网告警 | App Channel 共享 Topic 广播 + Kafka 下游消费 |
| 订单 / 个人业务提醒 | App Channel 私有 `personal:{user_id}` 或单聊 |
| AI 助手 / 流式回复 | 流式消息 + 透传 + 单聊/群聊 |
| 企业 SaaS 多 App | 多租户 `app_key` + 双通道 API + 可观测与审计 |

---

## 技术架构亮点（简图）

```text
                    ┌─────────────────────────────────┐
                    │     客户端（iOS / Android / Web）   │
                    └───────────────┬─────────────────┘
                                    │
              ┌─────────────────────┼─────────────────────┐
              │  HTTPS REST         │  WebSocket 二进制     │
              │  /api/v1            │  Protobuf Packet      │
              │  /internal/v1       │                       │
              ▼                     ▼                       │
     ┌────────────────────────────────────────┐            │
     │     IM 集群（水平扩展，多 Access 节点）    │◄───────────┘
     │   接入 → 业务 Dispatch → 存储 / 推送      │
     └───────────────┬──────────────────────────┘
                     │
         ┌───────────┼───────────┬──────────────┐
         ▼           ▼           ▼              ▼
    PostgreSQL    Redis       Kafka        APNs/FCM
    消息/会话/群   在线/序号    旁路事件      离线推送
```

**设计原则摘要**：

1. **实时走长连接，管理走 REST**——同一套 `Dispatch`，行为一致。  
2. **存业务消息，不存 Packet 信封**——协议可演进，数据模型稳定。  
3. **热路径少拷贝**——下行推送整包只编码一次，扇出传递 `packet_binary`。  
4. **旁路不挡主路**——发消息不等 Kafka；日志生产环境默认 warning 起打，成功路径走指标。

---

## 与常见方案的差异

| 维度 | 本系统 | 常见轻量方案 |
|------|--------|----------------|
| 协议 | 二进制 Protobuf + 完整 cmd 分区 | JSON over WS 或第三方 SDK 黑盒 |
| 群聊大扇出 | 树状扇出 + 批量推送（设计） | 单进程循环 push，规模受限 |
| 聊天室 | 独立语义，默认不落库 | 与群聊混用，历史难控 |
| 业务事件 | 独立 App Channel + Kafka | 塞进聊天消息或自建 MQTT |
| 可观测 | 指标 + 结构化日志 + trace_id | 依赖厂商控制台 |
| 部署 | K8s Release、可自建 | 多为纯 SaaS，难私有化 |
| 文档 | 协议 + 设计 + 实现 + 决策索引 | 往往只有 API 列表 |

---

## 开放与对接方式

| 对接方 | 方式 |
|--------|------|
| **移动端 / Web SDK** | WebSocket + `proto/` 生成各语言代码；REST `/api/v1` 对等 |
| **业务后端** | REST `/internal/v1`（踢人、封禁、代发、Channel 广播）；Kafka 消费 `im.*` Topic |
| **运维 / SRE** | `/metrics`、统一 JSON 日志、K8s 健康检查 |
| **二次开发** | 单仓 `apps/elixir/im`；模块边界见 [模块化架构](design/modular-architecture.md) |

---

## 当前状态（诚实说明）

| 项 | 状态 |
|----|------|
| 协议（`proto/`） | ✅ 已定义，CI `proto-check` 通过 |
| 设计文档 | ✅ 30+ 模块已评审或待评审（见 [design-decisions.md](design-decisions.md)） |
| Elixir 实现 | ✅ **Phase 0–13 完成**（核心协议/集群/运维；见 [PROGRESS](implementation/elixir/PROGRESS.md)） |
| 本地 K8s 依赖栈 | ✅ Redis / PostgreSQL 可 `mise run k8s-up` |
| 生产可用 | ⏳ 待规模压测归档、推送/Kafka 等 v1 deferred 项与运维验收 |

**适合现在接入的人**：愿意基于 **清晰协议与架构** 共建实现、或需要 **私有化 IM 蓝图** 的团队。  
**若需要明天就能上线的成品 SaaS**：请评估自研排期，或先用本仓库作技术选型与协议参考。

---

## 如何开始

```bash
# 1. 克隆仓库，安装工具链
mise install

# 2. 校验协议
mise run proto-check

# 3. 编译与测试（随实现推进逐步丰富）
mise run im:compile
mise run im:test
```

**按角色阅读**：

| 角色 | 路径 |
| --- | --- |
| **产品 / 业务** | 本文 → [架构总览](design/architecture-overview.md) §能力边界 |
| **客户端对接** | [协议规范](design/protocol/protocol.md) + [proto/](../proto/) → [http-api-reference](implementation/elixir/http-api-reference.md) |
| **服务端开发** | [文档总索引](README.md) → [module-map](module-map.md) → [PROGRESS](implementation/elixir/PROGRESS.md) |
| **运维部署** | [deploy/README.md](../deploy/README.md) → [deploy-guide](implementation/elixir/deploy-guide.md) |
| **AI / 协作者** | [agent.md](../agent.md) → [specs-index](specs-index.md) |

---

## 技术文档索引

| 分类 | 入口 |
| --- | --- |
| 文档总索引 | [README.md](README.md) |
| 功能 ↔ 代码对照 | [module-map.md](module-map.md) |
| 设计决策（DD-xxx） | [design-decisions.md](design-decisions.md) |
| 设计文档全集 | [design/README.md](design/README.md) |
| Elixir 实现 | [implementation/elixir/README.md](implementation/elixir/README.md) |
| Web 控制台 | [implementation/web/web-console.md](implementation/web/web-console.md) |
| 应用启动说明 | [apps/README.md](../apps/README.md) |
| 部署清单 | [deploy/README.md](../deploy/README.md) |
| Kiro 阶段规格 | [specs-index.md](specs-index.md) |

---

## 联系我们 / 参与共建

- 提交 Issue / PR 讨论协议与实现
- 按 [agent.md](../agent.md) 与 [PROGRESS](implementation/elixir/PROGRESS.md) 认领阶段性任务
- 架构变更请同步 [architecture-overview.md](design/architecture-overview.md) 与 [doc-sync-checklist](design/doc-sync-checklist.md)
