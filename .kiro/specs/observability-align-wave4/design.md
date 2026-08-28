# Design — Observability Align Wave4

## Burn 指标

| 事件 | 测量 | 位置 |
|------|------|------|
| `[:im, :msg_burn, :scheduled]` | count | `Jobs.MessageBurn.schedule` |
| `[:im, :msg_burn, :executed]` | count + lag_ms | `Jobs.MessageBurn.execute` |

`lag` = 执行时刻 − 调度时写入的 `due_at_ms`（≥0）。

## Audit

```text
IM.Audit.record(:auth_login | :auth_failed, fields)
  → Task.Supervisor → Repo.insert(audit_logs)
```

表：`audit_logs`（append-only）。
