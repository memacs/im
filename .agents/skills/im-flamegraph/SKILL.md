---
name: im-flamegraph
description: >-
  使用 Erlang/OTP 原生 Linux perf（BeamAsm +JPperf true）对 IM Release 采样并生成 CPU 火焰图 SVG。
  用户提到火焰图、性能剖析、perf、CPU 热点、P99 慢路径排查时使用。
auto_suggest: true
---

# IM 火焰图（Erlang 原生 perf）

IM 使用 **OTP BeamAsm 官方 perf 集成**，不是 `:erlang.trace/3` 或 eflame。

| 项 | 说明 |
| --- | --- |
| 机制 | `+JPperf true` → Linux `perf record` → `stackcollapse-perf.pl` → `flamegraph.pl` |
| 一键命令 | **`mise run flamegraph`**（见 [flamegraph.md](../../../docs/implementation/elixir/flamegraph.md)） |
| 官方文档 | [BeamAsm Linux perf support](https://www.erlang.org/doc/apps/erts/beamasm.html#linux-perf-support) |
| 脚本 | [`deploy/elixir/im/scripts/capture-flamegraph.sh`](../../../deploy/elixir/im/scripts/capture-flamegraph.sh) |
| 工具链 | [`apps/elixir/im/priv/flamegraph/`](../../../apps/elixir/im/priv/flamegraph/) |

---

## 何时使用

- 排查消息发送、扇出、WS 编解码、DB/Redis 等 **CPU 热点**
- 压测或线上低峰 **采样 30–60s** 生成可分享的 SVG
- **不要**在高峰期长时间采样；perf 开销低于 fprof，但仍占用 CPU

---

## 前置条件

1. **Linux**（K8s 节点 / OrbStack Linux VM / CI Linux）。macOS 宿主机无法直接 `perf record`。
2. BEAM **必须**带 `+JPperf true`（JIT 开启时生效）：
   ```bash
   IM_PERF_FLAMEGRAPH=true
   ```
   修改后 **须重启** Pod。
3. 运行脚本的环境有 `perf`、`perl`；K8s 模式要求 Pod 镜像含 perf。
4. K8s 内 `perf record` 可能需要节点 `kernel.perf_event_paranoid ≤ 2`。

---

## 一键采集

```bash
kubectl -n im-dev set env deployment/im IM_PERF_FLAMEGRAPH=true
kubectl -n im-dev rollout status deployment/im

mise run flamegraph
# 或 OPEN=1 DURATION=30 mise run flamegraph
```

---

## 命令参考

```bash
DURATION=45 NAMESPACE=im-dev mise run flamegraph
MODE=local DURATION=30 IM_PERF_FLAMEGRAPH=true ./deploy/elixir/im/scripts/capture-flamegraph.sh local
POD=im-xxx DURATION=60 ./deploy/elixir/im/scripts/capture-flamegraph.sh k8s
```

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `DURATION` | `30` | 采样秒数 |
| `OUTPUT_DIR` | `artifacts/flamegraph` | 输出目录 |
| `MODE` | `k8s` | `local` / `k8s` |
| `MERGE_SCHED` | `1` | 合并 scheduler 栈（OTP 官方 sed） |

---

## 产出

`perf.data`、`out.perf`、`out.folded`、`flame.svg`、`flame_sched.svg`（**优先看 sched 合并版**）

---

## 如何读图

- Erlang 函数前缀 **`$`**
- **越宽 = CPU 占比越高**
- 对比采样须同场景、同时长、同负载

---

## Agent 工作流

1. 确认 **Linux/K8s**，非 macOS 直跑 perf
2. 设 `IM_PERF_FLAMEGRAPH=true` 并 rollout
3. 运行 `mise run flamegraph`，**不要**手写 trace 剖析
4. 回报 `flame_sched.svg` 路径
