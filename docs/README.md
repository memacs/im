# IM 系统文档

基于 WebSocket + Protobuf 的即时通讯系统。

---

## 活索引（维护这三处即可）

| 文档 | 用途 |
|------|------|
| [product-overview.md](product-overview.md) | **产品介绍**（能力、优势、场景；对外推介首读） |
| [design/architecture-overview.md](design/architecture-overview.md) | **系统架构总览（活文档）**；系统级变更必同步 |
| [design-decisions.md](design-decisions.md) | **已确认设计模块**一览（状态、链到 design/*.md） |
| [implementation/elixir/PROGRESS.md](implementation/elixir/PROGRESS.md) | **实施进度**与下一项任务 |

协议规范：[design/protocol/protocol.md](design/protocol/protocol.md) + [proto/](../proto/)

---

## 文档分层

```text
proto/                              # 机器可读
docs/design/                        # 设计意图
docs/implementation/
  ├── monorepo-layout.md            # apps/ + deploy/ 仓布局
  └── elixir/
      ├── roadmap.md / PROGRESS.md
      └── project-structure.md      # apps/elixir/im/lib/
apps/
  ├── elixir/im/                    # 主 IM Mix 项目
  ├── elixir/loadtest/              # 压测（Phase 10）
  └── java/im/                      # 预留
deploy/elixir/im/                   # IM Release + K8s
```

**不维护**：本文件下的完整文件树（易过期）。模块列表见 [design/README.md](design/README.md) 与 [implementation/elixir/README.md](implementation/elixir/README.md)。

---

## 快速导航

| 分类 | 入口 |
|------|------|
| **产品介绍（对外推介）** | [product-overview.md](product-overview.md) |
| 协议规范 | [design/protocol/protocol.md](design/protocol/protocol.md) |
| 数据库 | [design/database/database-design.md](design/database/database-design.md) |
| 系统架构（**推荐首读**） | [design/architecture-overview.md](design/architecture-overview.md) |
| 系统架构（详细时序） | [design/system-design.md](design/system-design.md) |
| Elixir 实施 | [implementation/elixir/](implementation/elixir/) |
| Java（预留） | [implementation/java/](implementation/java/) |
| 部署 | [deploy/elixir/](../deploy/elixir/) |

---

## Proto

| 文件 | 内容 |
|------|------|
| [proto/common.proto](../proto/common.proto) | Packet、CmdType、ErrorCode |
| [proto/auth.proto](../proto/auth.proto) | 鉴权、心跳 |
| [proto/message.proto](../proto/message.proto) | 消息、ACK、已读、撤回、编辑、阅后即焚 |
| [proto/sync.proto](../proto/sync.proto) | 离线拉取 |
| [proto/group.proto](../proto/group.proto) / [room.proto](../proto/room.proto) / [friend.proto](../proto/friend.proto) | 群 / 室 / 好友 |
| [proto/channel.proto](../proto/channel.proto) | 应用通道 |
| [proto/event.proto](../proto/event.proto) | Kafka 事件（`im.app_events` 等） |
| [proto/event.proto](../proto/event.proto) | Kafka 事件（非 WS） |

校验：`mise run proto-check`

---

## 相关链接

- [根 README](../README.md)
- [设计文档索引](design/README.md)
- [Elixir 实现索引](implementation/elixir/README.md)
- [AI 协作约定](../agent.md)
