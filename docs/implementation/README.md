# IM 实现文档

本目录存放 IM 系统的**多语言实现文档**，每种语言独立子目录。

**活索引**：[design-decisions.md](../design-decisions.md)、[elixir/PROGRESS.md](elixir/PROGRESS.md)、[module-map.md](../module-map.md)、[specs-index.md](../specs-index.md)、[monorepo-layout.md](monorepo-layout.md)。

---

## 实现方案索引

| 语言 | 状态 | 说明 |
|------|------|------|
| [Elixir](elixir/) | **Phase 0–13 完成**（见 [PROGRESS](elixir/PROGRESS.md)） | Phoenix + 百万在线架构 |
| [Web Console](web/web-console.md) | **Phase 12 可演示**（`apps/web/im-console`） | 独立 SPA，协议能力演示与联调 |
| [Web 实现索引](web/README.md) | — | 前端实现文档入口 |
| [Java](java/) | 预留 | 待规划 |

---

## 协议设计(语言无关)

所有实现方案共用同一套协议设计:

| 文档 | 说明 |
|------|------|
| [协议规范](../design/protocol/protocol.md) | 完整协议规范 |
| [数据库设计](../design/database/database-design.md) | PostgreSQL + Redis 设计 |
| [系统设计](../design/system-design.md) | 系统架构设计 |
| [模块设计](../design/) | 各模块独立设计文档 |

---

## 如何选择实现方案

### Elixir 方案

**适用场景**:
- 百万级在线、高并发
- 需要长连接稳定性(Actor 模型天然优势)
- 快速迭代、热更新需求

**优势**:
- Erlang VM 的并发能力
- Phoenix.PubSub 跨节点通信简单
- 热更新、故障自愈

**劣势**:
- 学习曲线较陡
- 生态相对较小

### Java 方案

**适用场景**:
- 团队熟悉 Java 生态
- 需要丰富的中间件支持
- 企业级应用

**优势**:
- 生态丰富、人才储备充足
- Netty 高性能网络框架
- Spring Boot 开箱即用

**劣势**:
- 长连接管理复杂度较高
- 内存占用相对较大

---

## 实施原则

所有实现方案须遵循:

1. **协议优先**: 以 `proto/` 和 `docs/design/protocol/protocol.md` 为准
2. **规模前提**: 百万在线、高并发、多节点水平扩展
3. **文档一致**: 改代码必改文档,保持一致性
4. **验收标准**: 按各语言 roadmap 逐项验收

---

## 相关链接

- [文档总索引](../README.md)
- [协议设计](../design/)
- [AI 协作约定](../../AGENTS.md)
