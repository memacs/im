# Design: Phase 10

## 组件（`IM.LoadTest.*`）

| 模块 | 职责 |
| --- | --- |
| `Worker` | 单虚拟用户：REST 登录 → WS connect/AUTH → 场景动作 |
| `Controller` | 启动 Worker 池、汇总超时、触发报告 |
| `Metrics` | ETS 采样延迟、成功/失败计数、错误码 |
| `Reporter` | 输出 JSON（P50/P90/P99、QPS） |
| `Scenarios.ConnectionLoad` / `MessageFlood` | 场景入口 |
| `Mix.Tasks.Loadtest.Run` | CLI |

## 数据流

```
CLI → Controller → N × Worker → IM.Client (REST + Connection) → im /ws + /api
                         ↓
                      Metrics → Reporter → stdout / 文件
```

## 测试策略

- Metrics / Reporter：纯单元。
- Controller：短时 FakeWorker 或低并发 dry-run。
- 真机压测：对运行中的 IM 执行，不写入 CI 强制门槛（规模目标见 roadmap）。
