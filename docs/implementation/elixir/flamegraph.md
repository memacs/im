# CPU 火焰图（Erlang 原生 perf）

IM 支持基于 **OTP BeamAsm 官方 perf 集成** 的 CPU 火焰图，用于排查消息扇出、WebSocket 编解码、DB/Redis 等热点。机制为 `+JPperf true` → Linux `perf record` → FlameGraph 工具链 → SVG。

> 不是 `:erlang.trace/3` / eflame；对齐 [BeamAsm Linux perf support](https://www.erlang.org/doc/apps/erts/beamasm.html#linux-perf-support)。

---

## 一键采集

```bash
# 1. 确保 IM 已部署（本地联调）
mise run release-deploy

# 2. 开启 BEAM perf 符号（须 rollout 重启）
kubectl -n im-dev set env deployment/im IM_PERF_FLAMEGRAPH=true
kubectl -n im-dev rollout status deployment/im

# 3. 采集（默认 30s，输出到 artifacts/flamegraph/）
mise run flamegraph

# 4. 打开合并调度器版（推荐）
open artifacts/flamegraph/run-k8s-*/flame_sched.svg
```

采集完成后终端会打印 SVG 绝对路径。加 `OPEN=1` 可自动打开：

```bash
OPEN=1 DURATION=45 mise run flamegraph
```

---

## 环境变量

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `DURATION` | `30` | 采样秒数 |
| `NAMESPACE` | `im-dev` | K8s 命名空间 |
| `POD` | 自动 | 指定 Pod 名 |
| `OUTPUT_DIR` | `artifacts/flamegraph` | 输出目录 |
| `OPEN` | `0` | `1` = 完成后打开 SVG |
| `GENERATE_LOAD` | `1` | 采样前用 `im rpc` 制造 CPU 负载 |
| `PERF_EVENT` | 自动 | 无 HW PMU 时用 `cpu-clock:u`（OrbStack/aarch64） |

底层脚本：[`deploy/elixir/im/scripts/capture-flamegraph.sh`](../../../deploy/elixir/im/scripts/capture-flamegraph.sh)

---

## 产出文件

每次运行在 `artifacts/flamegraph/run-k8s-<pod>/` 下生成：

| 文件 | 说明 |
| --- | --- |
| `flame_sched.svg` | **优先查看**（scheduler 栈已合并） |
| `flame.svg` | 原始栈 |
| `perf.data` | perf 原始数据 |
| `out.perf` / `out.folded` | 中间产物 |

---

## 如何读图

- Erlang 函数以 **`$`** 为前缀（如 `$Elixir.Enum:-each/2-fun-0-/3`）
- **条越宽 = CPU 占比越高**
- 对比两次采样须同场景、同时长、相近负载

---

## 前置条件与限制

| 项 | 说明 |
| --- | --- |
| **Linux** | `perf record` 在 Pod 内执行；macOS 宿主机不能直接采样 |
| **`IM_PERF_FLAMEGRAPH=true`** | 通过 `rel/env.sh.eex` 向 vm.args 追加 `+JPperf true`；修改后须重启 Pod |
| **镜像** | Release 镜像含 `perl`、`linux-perf`（见 Dockerfile） |
| **Pod 权限** | `perf_event_open` 在 PSS **restricted** 下可能被拒；生产/low 环境需在具备 perf 权限的节点或专用 profile overlay 中采样 |
| **OrbStack/aarch64** | 无硬件 PMU，自动降级 `cpu-clock:u`；样本量低于 x86_64 生产节点 |

排查完成后建议关闭 JPperf（减少 JIT 开销）：

```bash
kubectl -n im-dev set env deployment/im IM_PERF_FLAMEGRAPH-
kubectl -n im-dev rollout status deployment/im
```

---

## 相关

| 文档 / 路径 | 说明 |
| --- | --- |
| [`mise.toml`](../../../mise.toml) | `flamegraph` / `im:flamegraph` 任务 |
| [`.agents/skills/im-flamegraph/SKILL.md`](../../../.agents/skills/im-flamegraph/SKILL.md) | Agent Skill |
| [`apps/elixir/im/rel/env.sh.eex`](../../../apps/elixir/im/rel/env.sh.eex) | `IM_PERF_FLAMEGRAPH` → vm.args |
| [deploy-guide.md §4](deploy-guide.md) | 健康检查与指标（与火焰图并列的运维能力） |
