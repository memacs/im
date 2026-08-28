# 依赖抽象层 - Elixir 实现

| 项 | 内容 |
|------|------|
| 语言 | Elixir |
| 设计文档 | [dependency-abstraction.md](../../design/dependency-abstraction.md)（**权威**） |
| Roadmap | Phase 0–9 按设计文档分阶段引入 Behaviour |

> **文档分级**：边缘模块 impl。接口契约与分阶段策略见设计文档；本文仅列模块映射与测试要点。

---

## 模块映射

| Behaviour / Facade | 默认实现 | 用途 | 引入 Phase |
| --- | --- | --- | --- |
| `IM.Auth` | `IM.Auth.Token` | REST/WS 鉴权 | 2 |
| `IM.Stores.MessageStore` | `IM.Stores.MessageStore.Postgres` | 消息落库 | 3 |
| `IM.Cache` | `IM.Cache.Redis` | 序列号、在线态 | 4+ |
| `IM.EventBus` | `IM.EventBus.Kafka` | Kafka 旁路 | 9 |

**约束**：`IM.Services.*` 只依赖 Behaviour / Facade，不直接 `use Redix` / `use Broadway`。

---

## 测试要点

- **DI 优先**：Service 通过 Behaviour / Facade 拿依赖；测试默认 **内存实现** 或 `config/test.exs` 切换，不连真实 Redis/Kafka。
- **Mox 边界**：**仅**进程外、不可控边界（如远程 HTTP 客户端）用 Mox；其余优先手写 `IM.Stores.*.Memory`、`IM.Cache.Memory` 等。
- **禁止 ExMachina**：造数用手写 `test/support` 工厂函数或 Context 辅助（如 `IM.Fixtures`、`IM.MessageContextFixtures`），与 Ecto changeset 路径一致。
- **禁止 sleep 同步**：异步用 `assert_receive` / `GenServer.call`；不得 `Process.sleep` 赌时序。仅真实时间流逝场景可 sleep，并注释原因。
- 每个 Behaviour 须有可替换实现；新增外部依赖时：先补设计文档 §6，再补 Behaviour + 测试双实现。

---

## 目录（P0-05 占位）

```text
lib/im/
├── auth/              # IM.Auth behaviour
├── stores/            # IM.Stores.*
├── cache.ex           # IM.Cache facade
└── event_bus/         # IM.EventBus（Phase 9）
```

详见 [project-structure.md](project-structure.md)。
