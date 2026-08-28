# Java 实现文档

基于 Java 的 IM 服务端实现（**预留**，尚未开始编码）。

> **当前可用实现**：请使用 [Elixir](../elixir/) 或参考其 [apps/elixir/im/README.md](../../apps/elixir/im/README.md)。

---

## 文档导航

| 文档 | 说明 |
| --- | --- |
| [docs/README.md](../../README.md) | 文档总索引 |
| [module-map.md](../../module-map.md) | 功能 ↔ 设计 ↔ 代码（语言无关部分适用） |
| [protocol.md](../../design/protocol/protocol.md) | 协议规范（Java 须对齐） |
| [database-design.md](../../design/database/database-design.md) | PostgreSQL + Redis 设计 |
| [architecture-overview.md](../../design/architecture-overview.md) | 系统架构（语言无关） |
| [apps/java/im/README.md](../../../apps/java/im/README.md) | Java 应用占位 |
| [deploy/java/README.md](../../../deploy/java/README.md) | Java 部署占位 |

---

## 技术栈（待定）

| 组件 | 候选方案 | 说明 |
| --- | --- | --- |
| 框架 | Spring Boot / Netty | Web 框架或网络框架 |
| 序列化 | Protobuf | 与 `proto/` 同源 |
| 连接管理 | Netty | WebSocket 接入 |
| 消息队列 | Kafka | 旁路事件 |
| 缓存 | Redis / Redisson | 序列号、在线状态 |
| 数据库 | PostgreSQL + MyBatis / JPA | 消息存储 |

---

## 实施规划（待创建）

Java 实现启动前建议：

1. 复制 Elixir [roadmap.md](../elixir/roadmap.md) 结构，创建 Java 版 roadmap / PROGRESS
2. 在 [module-map.md](../../module-map.md) 登记 Java 代码路径
3. 按 Phase 在 `.kiro/specs/` 创建对应 spec（见 [specs-index.md](../../specs-index.md)）

目录布局可参考 [project-structure.md](../elixir/project-structure.md) 的分层思想（Protocol → Dispatch → Services → Delivery）。

---

## 相关链接

- [Elixir 实现（当前主推）](../elixir/README.md)
- [monorepo-layout.md](../monorepo-layout.md)
- [design-decisions.md](../../design-decisions.md)
