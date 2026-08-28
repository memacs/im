# Java 实现文档

基于 Java 的 IM 服务端实现(预留)。

---

## 技术栈(待定)

| 组件 | 候选方案 | 说明 |
|------|---------|------|
| 框架 | Spring Boot / Netty | Web 框架或网络框架 |
| 序列化 | Protobuf | 协议序列化 |
| 连接管理 | Netty | WebSocket 接入 |
| 消息队列 | Kafka | 旁路事件 |
| 缓存 | Redis / Redisson | 序列号、在线状态 |
| 数据库 | PostgreSQL + MyBatis / JPA | 消息存储 |

---

## 文档索引(待补充)

| 文档 | 说明 |
|------|------|
| [project-structure.md](../elixir/project-structure.md) | 目录布局参考（Elixir）；Java 待规划 |
| roadmap.md | 分阶段实施路线图(待创建) |
| PROGRESS.md | 实施进度看板(待创建) |

---

## 实施规划(待补充)

TBD

---

## 相关链接

- [协议设计](../design/protocol/protocol.md)
- [数据库设计](../design/database/database-design.md)
- [Elixir 实现](../elixir/)
