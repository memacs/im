# 本地开发常见陷阱（Elixir / OrbStack）

> 记录真实踩坑，避免 AI 与开发者重复犯错。  
> 相关：[`mise.toml`](../../../mise.toml)、[`deploy/elixir/im/scripts/resolve-pg-port.sh`](../../../deploy/elixir/im/scripts/resolve-pg-port.sh)

---

## Postgres 端口：5432 vs 15432

### 现象

运行 `mise run test` / `mix test` 报错：

```text
** (DBConnection.ConnectionError) tcp connect (localhost:5432): connection refused
```

开发者或 AI 误判为「OrbStack 没有 DB」或「Postgres 未启动」。

### 根因

| 层级 | 实际监听 |
|------|----------|
| K8s 集群内 | `postgres.im-dev:5432` |
| 本机（经 port-forward） | **`localhost:15432`** |
| `config/test.exs` / `dev.exs` 默认 | `PGPORT` 未设时 → **`5432`** |

Postgres **在 OrbStack 里通常是有的**，但 **不会**直接占本机 5432。  
未设 `PGPORT=15432` 且未跑 `pg-forward` 时，Mix 会去连本机 5432 → 失败。

### 事件（AI 验证失误）

- 跑 `mise run im:test` 未 export `PGPORT`
- 得出「DB 不可用 / 测试无法跑通」的错误结论
- 实际上 `nc -z localhost 15432` 已成功，仅 **`PGPORT=15432 mise run im:test`** 即可绿

**教训**：本地验证 `mix test` 前必须先确认 **`PGPORT` 与 port-forward 端口一致**，不能只看默认 5432。

### 正确做法

**终端 A（常驻）：**

```bash
mise run k8s-up          # 首次或 namespace 空时
mise run pg-forward      # K8s Postgres → localhost:15432（断线自动重连）
```

**终端 B：**

```bash
mise run test            # mise 任务会自动 resolve PGPORT（15432 优先，其次 5432）
mise run ci
```

手动指定（可选）：

```bash
PGPORT=15432 mise run test    # OrbStack
PGPORT=5432 mise run test     # GHA / 本机原生 Postgres
```

### 自动化

以下 mise 任务在运行前 **`source resolve-pg-port.sh`**：

- `im:test`、`test`、`check`、`ci`（经 im:test）
- `im:server`、`ecto-*`、`test-watch`、`test-failed`、`console`

逻辑：

1. 已设 `PGPORT` → 不覆盖（CI 用 `PGPORT=5432`）
2. `localhost:15432` 可达 → `PGPORT=15432`（OrbStack + pg-forward）
3. `localhost:5432` 可达 → `PGPORT=5432`（GHA service）
4. 都不可达 → 明确报错 + 指向本文

---

## MIX_ENV 勿在 mise 全局固定为 test

见 [`mise.toml`](../../../mise.toml) `[env]` 注释：`mix test` 会自动切 `:test`；  
全局 `MIX_ENV=test` 会导致 Endpoint 在错误环境起监听、连错库。

---

## 相关链接

- [README.md](../../../README.md) — 本地开发速查
- [deploy/elixir/im/k8s/README.md](../../../deploy/elixir/im/k8s/README.md) — pg-forward
- [agent.md](../../../agent.md) — AI 协作约束
