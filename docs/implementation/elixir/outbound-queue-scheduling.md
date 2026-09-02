# 出站调度：OutboundQueue + PacketTransport 优先级发送与丢弃

> 适用模块：`apps/elixir/im/lib/im/delivery/outbound_queue.ex`（单连接出站 WFQ 状态机）、
> `apps/elixir/im/lib/im_web/packet_transport.ex`（WebSocket 进程主循环）。
> 关联设计文档：[`modular-architecture.md`](modular-architecture.md)（Delivery 分层）、[`protocol.md`](../../design/protocol/protocol.md) §消息投递优先级。

---

## 一、总体架构：谁依赖谁

[`PacketTransport`](https://github.com/memacs/im/blob/main/apps/elixir/im/lib/im_web/packet_transport.ex)
是每个 WebSocket 连接进程的主循环（`@behaviour WebSock`），路径 `/ws`。它的进程 state 里挂一个
`%{outbound: OutboundQueue.new()}` 结构体，**所有服务端下行（PUSH/KICK/ACK 除外）全量经过
OutboundQueue 排队再写回 socket**。

> 设计决策（P3-09）：把队列**放在连接进程 state，不做独立 GenServer**——避免每次 PUSH 都跨进程
> 拷贝 protobuf binary；调度逻辑纯函数，便于测试和热更新 `defstruct` 字段。

### 1.1 四种下行路径

`PacketTransport.handle_info/2` 收到的下行消息（均会进入 OutboundQueue）：

| handle_info 子句 | 来源 | 优先级 |
| --- | --- | --- |
| `{:im_push, bin}` / `{:im_push, bin, meta}`（L112–118） | 单聊 / 群聊 PUSH、ACK 旁路下行 | `meta[:priority]`，缺省 `:normal` |
| `{:im_room_push, bin, meta}`（L120–126） | 聊天室定向 PUSH | 同上；先过 `room_deliver?` 过滤 `exclude_device_id` / `target_users`，不匹配则直接丢弃（不到达队列） |
| `{:channel_push, bin}`（L128–131） | **App Channel 第三方应用透传** | **强制 `:low`**（注释明确："可丢，超 outbound_max_depth 时优先丢弃"） |
| `Handler.handle_packet -> {:reply, bin}`（L42） | 客户端请求的 **同步响应**（如 CMD_MSG_SEND 的 CMD_MSG_ACK） | **绕过队列直接 push**（不占优先级配额） |

### 1.2 HIGH 快路径（低负载零延迟优化）

[PacketTransport `push_via_queue/3` L165–168](https://github.com/memacs/im/blob/main/apps/elixir/im/lib/im_web/packet_transport.ex#L165-L168)：

```elixir
# 队列空时 HIGH 可直写，降低紧急推送延迟
if OutboundQueue.empty?(state.outbound) and
     OutboundQueue.normalize_priority(priority) == :high do
  {:push, {:binary, bin}, refresh_idle(state)}
else
  ...enqueue + drain...
end
```

含义：当 `state.outbound` 当前积压为 0 + 本条优先级归一化后为 HIGH，
**不进队列**，直接 `{:push, {:binary, bin}, ...}` 写回 socket。

目的：ACK、踢人指令、`:CMD_ERROR` 等紧急推送在低负载下**零延迟**；
一旦队列里有积压（哪怕只有一条 LOW），就走完整的 WFQ 排队出队流程。

---

## 二、三条优先级带与权重

### 2.1 数据结构（OutboundQueue defstruct）

[`outbound_queue.ex` L31–38](https://github.com/memacs/im/blob/main/apps/elixir/im/lib/im/delivery/outbound_queue.ex#L31-L38)：

```elixir
defstruct high: [],            # HIGH 带：ACK、踢人、已读回执
          normal: [],          # NORMAL 带：聊天消息主路径（单聊/群聊/聊天室）
          low: [],             # LOW 带：App Channel 透传、第三方广播（可丢）
          deficit: %{high: 0, normal: 0, low: 0},  # WFQ 虚拟时间（信用点）
          last_band: nil,      # 上一条出队的带
          burst_count: 0,      # 同带连续出队计数（防饿死）
          depth: 0,            # 三带总条数（避免每次 sum）
          dropped: 0           # 累计丢弃条数（可观测性）
```

每个条目（`item`）L13–18：

```elixir
@type item :: %{
        required(:packet_binary) => binary(),  # 已 encode 的 Packet 字节
        required(:priority) => band(),         # :high / :normal / :low
        required(:inbox_seq) => non_neg_integer(),
        required(:enqueued_at_ms) => integer() # 入队 wall 时间
      }
```

### 2.2 权重（Application env 可覆盖）

[`outbound_queue.ex` L335–338](https://github.com/memacs/im/blob/main/apps/elixir/im/lib/im/delivery/outbound_queue.ex#L335-L338)：

| band | weight | env key | 默认 |
| --- | --- | --- | --- |
| `:high` | 8 | `priority_weight_high` | 8 |
| `:normal` | 4 | `priority_weight_normal` | 4 |
| `:low` | 1 | `priority_weight_low` | 1 |

权重和 = **13**。持续积压时，三者按比例分得出队配额：

- HIGH ≈ 62%（8/13）
- NORMAL ≈ 31%（4/13）
- LOW ≈ 8%（1/13）

**保证 LOW 堆积如山也抢不走聊天消息的带宽**；同时 LOW 不会完全饿死（至少有 1/13 的份额，加上 aging 的提级）。

### 2.3 优先级归一化（外部入参）

[`normalize_priority/1`](https://github.com/memacs/im/blob/main/apps/elixir/im/lib/im/delivery/outbound_queue.ex#L344-L353)
把调用方传的 Protobuf 枚举 / 整数 / 原子，统一归一成 `:high / :normal / :low`：

| 入参 | 归一化结果 |
| --- | --- |
| `:high`、`:MSG_PRIORITY_HIGH`、`1` | `:high` |
| `:normal`、`:MSG_PRIORITY_NORMAL`、`0`、其它未知值 | `:normal` |
| `:low`、`:MSG_PRIORITY_LOW`、`2` | `:low` |

上游：`IM.Delivery.Push`、Room PubSub、App Channel 在构造 `meta` 时填对应优先级。

---

## 三、入队：排序 + 溢出丢弃

### 3.1 保持有序（按 inbox_seq + enqueued_at_ms）

[`enqueue/2` L60–75](https://github.com/memacs/im/blob/main/apps/elixir/im/lib/im/delivery/outbound_queue.ex#L60-L75)：

```elixir
def enqueue(%__MODULE__{} = q, item) when is_map(item) do
  band = normalize_priority(Map.get(item, :priority, :normal))
  entry = %{packet_binary: ..., priority: band, inbox_seq: ..., enqueued_at_ms: ...}
  q
  |> put_band(band, insert_sorted(get_band(q, band), entry))
  |> Map.update!(:depth, &(&1 + 1))
  |> maybe_drop_overflow()
end
```

[`insert_sorted/2`](https://github.com/memacs/im/blob/main/apps/elixir/im/lib/im/delivery/outbound_queue.ex#L305-L313)
用 `{inbox_seq, enqueued_at_ms}` 做升序 key（小在前）：

```elixir
defp insert_sorted([h | t] = list, item) do
  if {item.inbox_seq, item.enqueued_at_ms} <= {h.inbox_seq, h.enqueued_at_ms} do
    [item | list]
  else
    [h | insert_sorted(t, item)]
  end
end
```

**为什么要 sort**：WFQ 轮转是 "从 band 头取一条"，如果 inbox_seq 1 和 3 同时积压在 HIGH 带，
必须保证 1 先发、3 后发——否则客户端会看到"消息 3 先到、消息 1 后跳出来"的展示错乱。
aging 提级后，进入新 band 也走 `insert_sorted`（见 §4.1），保证 inbox_seq 全局有序。

### 3.2 溢出丢弃：只丢 LOW 带最旧条目

[`maybe_drop_overflow/1` L287–303](https://github.com/memacs/im/blob/main/apps/elixir/im/lib/im/delivery/outbound_queue.ex#L287-L303)：

```elixir
defp maybe_drop_overflow(%__MODULE__{} = q) do
  max = cfg(:outbound_max_depth, 10_000)
  if q.depth <= max or q.low == [] do
    q
  else
    [_old | rest] = q.low
    :telemetry.execute([:im, :outbound, :dropped], %{count: 1}, %{priority: :low, host: ...})
    maybe_drop_overflow(%{q | low: rest, depth: q.depth - 1, dropped: q.dropped + 1})
  end
end
```

规则：

1. 超过 `outbound_max_depth`（默认 **10,000**）才丢
2. **只丢 `LOW` 链表头（最旧）的条目**
3. 递归丢，直到 `depth <= max` 或 **LOW 为空**
4. **HIGH / NORMAL 永远不会因 overflow 被丢**
5. 每条丢弃触发 `[:im, :outbound, :dropped]` telemetry，Prometheus 可告警

**设计意图**：客户端长时间不读（后台挂起 / 网速极差）会造成积压。此时应保证：

- 聊天消息（NORMAL + 老化升到 HIGH）**不丢** → 用户体验红线
- App Channel 广播（LOW）**可容忍丢** → 第三方通知"等了太久就没必要再发"
- ACK / KICK（HIGH 快路径 + HIGH 带）**不丢** → 协议 QoS 依赖

---

## 四、出队调度：四阶段流水线

PacketTransport 每次 enqueue 一条后立即：

```elixir
q = OutboundQueue.enqueue(state.outbound, item)                # 入队
max_burst = Application.get_env(:im, :priority_max_burst, 16)
{bins, q2} = OutboundQueue.drain(q, max_burst)                 # 拉一批出队
```

[`drain/2`](https://github.com/memacs/im/blob/main/apps/elixir/im/lib/im/delivery/outbound_queue.ex#L80-L90)
内部按顺序做四件事（流水从左到右）：

```text
drain(q, max_n)
  │
  ├─ 1) apply_aging(q, now)            —— 包等待太久自动提级（防饿死）
  │
  ├─ 2) maybe_coalesce(q)              —— 深度 >32 时合并聊天消息为 MsgPushBatch
  │
  └─ 3) do_drain(q, max_n, [], now)    —— WFQ 轮转逐条出队
         │
         └─ pick_next(q)
               ├─ select_band     —— 同带 burst 上限（防连吃 16 条）
               └─ best_deficit    —— 选 deficit 最大（信用最高）+ band_rank 平局
```

### 4.1 Aging（优先级老化 / 自动提级）

[`apply_aging/2` L241–285](https://github.com/memacs/im/blob/main/apps/elixir/im/lib/im/delivery/outbound_queue.ex#L241-L285)。
三条阈值（毫秒，可通过 Application env 覆盖）：

| 升级路径 | 默认等待 | env key |
| --- | --- | --- |
| LOW → NORMAL | 2,000 | `priority_aging_low_ms` |
| LOW → HIGH | 5,000 | `priority_aging_low_to_high_ms` |
| NORMAL → HIGH | **500** | `priority_aging_normal_ms` |

> **为什么 NORMAL→HIGH 最短（0.5s）？**
> NORMAL 是**聊天消息主路径**，用户 1 秒以内体验最敏感；
> LOW 是"可丢"的频道广播，等 2~5 秒再提级，让它平时占不到便宜，但也不会无限期饿死。

实现用一次 `Enum.reduce` 遍历 LOW / NORMAL，按三段条件分流：

```elixir
{low_keep, to_high_from_low, to_normal_from_low} =
  Enum.reduce(q.low, {[], [], []}, fn item, {keep, hi, no} ->
    wait = now - item.enqueued_at_ms
    cond do
      wait >= low_to_high   -> {keep, [item | hi], no}
      wait >= low_to_normal -> {keep, hi, [item | no]}
      true                  -> {[item | keep], hi, no}
    end
  end)
```

提级后的条目**用 `insert_many`（= 反复 `insert_sorted`）插入新 band**，
保证 inbox_seq 顺序不被打乱。
每次提级触发 `IM.Telemetry.Outbound.aged/3` 埋点。

### 4.2 Coalesce（批量合并 MsgPushBatch）

[`maybe_coalesce/1` L92–104](https://github.com/memacs/im/blob/main/apps/elixir/im/lib/im/delivery/outbound_queue.ex#L92-L104)：
当 **队列总深度 > `outbound_coalesce_depth`（默认 32）** 时，把**同一 band 内连续的 `CMD_MSG_PUSH`**
合并成 `MsgPushBatch`。

- 单批上限：`push_batch_max`（默认 **50** 条消息）
- 合并流程：`extract_single_push`（decode 确认是 `CMD_MSG_PUSH` + 解出 `ChatMessage`）
  → `flush_push_buf`（按 50 分块 → `encode_coalesced`）
- `encode_coalesced`：把多条 `ChatMessage` 塞进 `MsgPushBatch.messages`，
  用第一条的 `conv_id` 当 `route_key`，然后 `Codec.encode` 回 binary
- **如果 encode 失败就回退原样**，不因为合并而丢消息

目的：聊天室大群扇出时，每条 protobuf 头 + WebSocket 帧头占比显著，合并后：

- PUSH 条数 ↓（50 条变 1 条）
- 客户端也只需要 decode 一次 batch
- 对项目一量化成果"大群 5000 人发消息 P99<200ms"有直接贡献

### 4.3 WFQ 选带（核心调度：Deficit Round Robin）

每条出队由 [`pick_next/1`](https://github.com/memacs/im/blob/main/apps/elixir/im/lib/im/delivery/outbound_queue.ex#L193-L220) 决定从谁的头取：

```elixir
defp pick_next(q) do
  bands = nonempty_bands(q)               # [:high, :normal, :low] 中非空子集
  band  = select_band(q, bands)           # 决定本轮发哪个带
  [item | rest] = get_band(q, band)
  sum_w = weight_sum()                    # 8+4+1 = 13

  # WFQ 记账：先扣一轮基础（sum_w），再加自己权重（8/4/1）
  deficit =
    q.deficit
    |> Map.update!(band, &(&1 - sum_w))   # "轮次结束"
    |> Map.update!(band, &(&1 + weight(band)))

  burst_count = if q.last_band == band, do: q.burst_count + 1, else: 1
  q2 = q |> put_band(band, rest)
           |> Map.put(:deficit, deficit)
           |> Map.put(:last_band, band)
           |> Map.put(:burst_count, burst_count)
           |> Map.update!(:depth, &(&1 - 1))
  {item, q2}
end
```

`best_deficit/2` [L235–239](https://github.com/memacs/im/blob/main/apps/elixir/im/lib/im/delivery/outbound_queue.ex#L235-L239)：

```elixir
defp best_deficit(q, bands) do
  bands
  |> Enum.sort_by(fn b -> {-Map.fetch!(q.deficit, b), band_rank(b)} end)
  |> hd()
end
```

**先按 deficit 从大到小**（谁信用最多先发），**再按 band_rank**（HIGH=0、NORMAL=1、LOW=2）
打平局——**deficit 相同时 HIGH 永远领先**。

### 4.4 Burst 上限（防同带饿死他带）

[`select_band/2` L222–233](https://github.com/memacs/im/blob/main/apps/elixir/im/lib/im/delivery/outbound_queue.ex#L222-L233)：

```elixir
defp select_band(q, bands) do
  max_burst = cfg(:priority_max_burst, 16)
  if q.last_band && q.burst_count >= max_burst do
    case Enum.reject(bands, &(&1 == q.last_band)) do
      [] -> best_deficit(q, bands)          # 只有它一家，继续发
      others -> best_deficit(q, others)     # 还有别的 band，就换下一家
    end
  else
    best_deficit(q, bands)
  end
end
```

含义：即便 HIGH 带里积压几千条，每 16 条后也**必须至少插一条 NORMAL 或 LOW**
（除非只有 HIGH 非空）。避免出现反直觉场景：

> "我的聊天消息被卡在 App Channel 广播后面"
> ——实际上 NORMAL 消息是聊天主路径（见 2.2 的权重），burst 限制让这种饿死场景
> 有硬上限：最多被 16 条连续 HIGH 顶一次，下次一定轮到 NORMAL。

### 4.5 观测埋点

三条出队埋点 + 两条入队埋点：

| 位置 | 事件 / 函数 | 指标含义 |
| --- | --- | --- |
| do_drain L187-188 | `IM.Telemetry.Outbound.wait_ms(wait, item.priority)` | 单条包的端到端等待时长（入队 → 出队），按 priority 分桶 |
| pick_next 每次出队 | `depth -= 1`（state 维护） | 实时积压条数 |
| PacketTransport L181-185 | `IM.Telemetry.Outbound.depth(%{high, normal, low})` | 每次 drain 结束上报三带深度（按 host 聚合） |
| apply_aging L275-282 | `IM.Telemetry.Outbound.aged(from, to, n)` | 老化提级条数 |
| maybe_drop_overflow L295-299 | `:telemetry.execute([:im, :outbound, :dropped], …)` | 因 overflow 丢 LOW 条 |

---

## 五、丢弃决策总表

| 场景 | 发生位置 | 丢什么 | 是否会丢 HIGH/NORMAL |
| --- | --- | --- | --- |
| 队列深度 > `outbound_max_depth`(10000) | `maybe_drop_overflow` | **LOW 带最旧条**；LOW 空后停 | ❌ 绝不会丢 HIGH/NORMAL |
| App Channel 被强制标 LOW + 深积压 | PacketTransport L130 | 同上（属于 LOW 带） | ❌ |
| `room_deliver?` 过滤（exclude/targets 不匹配） | PacketTransport L120-126 | **未进入队列就丢**；聊天室定向推送，对非目标用户丢弃 | N/A（不属于优先级调度） |
| NORMAL 消息等 0.5s？ | aging | **不丢，升级到 HIGH 提前出队** | 保护 |
| LOW 消息等 2s？ | aging | 升级到 NORMAL | 保护 |
| LOW 消息等 5s？ | aging | 升级到 HIGH | 保护（至少一次投递） |
| WebSocket frame decode 失败 | PacketTransport L67-73 | **直接关连接**，这条包丢（解码失败无法知道 cid） | N/A（传输错误） |
| 未认证超时（auth_timeout_ms） | PacketTransport L82-84 | **关连接**，state 上积压的消息全部丢失（用户都没登录，不该攒 PUSH） | 连接级处置 |
| idle 超时（idle_timeout_ms） | PacketTransport L88-90 | **关连接**，全部 PUSH 丢失（客户端已 90s 无心跳） | 连接级处置 |

> 连接级处置（上末两行）：关闭 WebSocket 连接时，OutboundQueue 里攒的 PUSH **不再补发**。
> 业务兜底靠**离线拉取**（[`offline-pull.md`](offline-pull.md)）——客户端重连后
> 走 `CMD_SYNC_OFFLINE` 从 `inbox` 表补未读 PUSH；App Channel LOW 条在补发体系里默认不存（因此定义为"可丢"）。

---

## 六、可调参数一览（Application.get_env(:im, key)）

| 参数 | 默认 | 作用 |
| --- | --- | --- |
| `outbound_max_depth` | 10,000 | 三带总深度上限；超出循环丢弃最旧 LOW |
| `outbound_coalesce_depth` | 32 | 深度 > 此值触发 MsgPushBatch 合并 |
| `push_batch_max` | 50 | 每次合并的最大 ChatMessage 数 |
| `priority_max_burst` | 16 | 同带连续出队上限（防饿死） |
| `priority_weight_high/normal/low` | 8/4/1 | WFQ 权重 |
| `priority_aging_normal_ms` | 500 | NORMAL→HIGH 等待时间 |
| `priority_aging_low_ms` | 2,000 | LOW→NORMAL 等待时间 |
| `priority_aging_low_to_high_ms` | 5,000 | LOW→HIGH 等待时间 |
| `auth_timeout_ms` | 10,000 | 连接建立后必须登录的时限 |
| `idle_timeout_ms` | 90,000 | 无收发后自动断连（每次 push/recv 重置） |

覆盖方式：在 `config/runtime.exs` 或 `config/dev/test/prod.exs` 中

```elixir
config :im, outbound_max_depth: 20_000
config :im, priority_max_burst: 32
```

Release 部署时可用环境变量注入（见 [runtime.exs](https://github.com/memacs/im/blob/main/apps/elixir/im/config/runtime.exs) 的 `System.get_env` 模式）。

---

## 七、与设计决策的对应关系

| 设计点 | 对应位置 | 本文章节 |
| --- | --- | --- |
| P3-09 单连接出站调度（P3-09） | moduledoc L2 | 全文 |
| 热路径少拷贝 / binary 透传 | `packet_binary` 直接进队列，`push_via_queue` 仅构造 meta | §1 + §3 |
| HIGH/NORMAL 不丢（聊天 + 同步 ACK） | `maybe_drop_overflow` 只丢 LOW + aging 把 NORMAL 提 HIGH | §3.2 + §4.1 + §5 |
| App Channel 可丢（业务定义） | PacketTransport L128-131 强制 :low | §1.1 |
| 双通道共用 Dispatch（快路径 bypass） | Handler.reply 直推 vs PUSH 走 WFQ | §1.1 + §1.2 |
| 观测体系（Prometheus + JSON 日志） | 多处 telemetry / IM.Telemetry | §4.5 |

---

## 八、堆积场景分析（修复前快照：当前调用路径下不会堆积）

> **2026-09-02 方案 B 周期 drain 修复前的快照**。本节描述的是"入队后立即 drain(16)"工作模式下
> OutboundQueue 不堆积的根因分析，**保留作为根因对照**。修复后队列会在 `:drain_tick` 周期（默认 50ms）
> 内堆积，aging/coalesce/max_depth/WFQ 全部生效；**Bandit 不暴露 socket 可写状态导致的残留 gap 详见 [§9.9](#99-残留-gapbandit-不暴露-socket-可写状态g-40-residual)**。

> **核心结论**：按修复前 `push_via_queue` 的实现逻辑，OutboundQueue **实际上不会堆积**。
> `aging`、`coalesce_depth=32`、`max_depth=10000` 这些阈值在修复前调用路径下**永远不会触发**，
> 它们是**防御性兜底 + 未来扩展接口**，不是当时堆积场景的反推。

### 8.1 为什么当前不会堆积

**生产环境 `OutboundQueue.enqueue` 的调用点只有 1 处**：
[packet_transport.ex:177](https://github.com/memacs/im/blob/main/apps/elixir/im/lib/im_web/packet_transport.ex#L177)
的 `push_via_queue`，且**每次 enqueue 1 条后立即 drain(16)**。

调用流程：

```elixir
q  = OutboundQueue.enqueue(state.outbound, item)  # +1 条
{bins, q2} = OutboundQueue.drain(q, max_burst)    # 取 min(depth, 16) 条
```

| 队列原状态 | 入队 | drain 取 | 队列新状态 |
| --- | --- | --- | --- |
| 0 条 | +1 | 1 条（队列只有 1 条） | **0 条** |
| 0 条（再来） | +1 | 1 条 | **0 条** |
| ... 永远循环 | ... | ... | **始终为 0** |

`drain(q, 16)` 的语义是"最多取 16 条"，不是"必须取 16 条"——队列只有 1 条时只取 1 条就停止（见 [`do_drain` L178-179](https://github.com/memacs/im/blob/main/apps/elixir/im/lib/im/delivery/outbound_queue.ex#L178-L179) 的 depth=0 终止条件）。

### 8.2 突发批量不会堆积（GenServer 顺序消费 mailbox）

疑问：用户在 50 个活跃聊天室，同一秒收到 50 条 `{:im_room_push}` 会不会堆积？

**不会**。GenServer mailbox 是待处理消息队列，PacketTransport **顺序消费** mailbox：

```
mailbox: [push_1, push_2, ..., push_50]

处理 push_1: enqueue 1 → drain 1 → 队列 0
处理 push_2: enqueue 1 → drain 1 → 队列 0
...
处理 push_50: enqueue 1 → drain 1 → 队列 0
```

每次处理都"入 1 出 1"，队列始终为 0。**Bandit 的 frames 队列会堆积**（因为 socket write 跟不上），但 OutboundQueue 不会。

### 8.3 LOW + WFQ 整形也不会堆积

之前我推测"LOW 被 WFQ 整形到 1/13 速率会堆积"是错的。

实际上：App Channel 推 100 条 LOW → GenServer 顺序消费 → 每条入队 1 → drain 16（实际取 1，因为队列只有 1 条 LOW）→ 队列 0。

**WFQ 的权重 8/4/1 只在队列同时有多带积压时才生效**。单条入队 + 立即 drain 的工作模式下，每条 LOW 进来时队列都是空的，drain 取 1 条就走——根本没机会调用 `select_band` 做多带 WFQ 选择。

### 8.4 那 aging / coalesce / max_depth 是为什么设计的？

查测试代码 [outbound_queue_test.exs](https://github.com/memacs/im/blob/main/apps/elixir/im/test/im/delivery/outbound_queue_test.exs)：
单测里 `Enum.reduce(1..20, OutboundQueue.new(), fn i, acc -> ... end)` 是**直接连续 enqueue 20 条不 drain**，
测纯函数行为，**不是真实调用路径**。

这些参数的真实定位：

| 参数 | 实际作用 |
| --- | --- |
| `priority_max_burst=16` | 防御性：万一未来加入 batch_push 路径，限制单次 drain 上限，避免一次取 1000 条压垮 socket write |
| `outbound_coalesce_depth=32` | 未来扩展：万一未来 batch_push 让队列堆到 32，触发 MsgPushBatch 合并减少帧数 |
| `priority_aging_normal_ms=500ms` | 防御性 + 未来扩展：万一未来队列真堆了，NORMAL 0.5s 升 HIGH 防饿死 |
| `priority_aging_low_to_high_ms=5s` | 同上，LOW 5s 兜底逃生 |
| `outbound_max_depth=10000` | 防御性：万一未来 bug 让队列堆积，丢最旧 LOW 防 OOM |

> **三层定位**：
> 1. **防御性兜底**：万一未来代码 bug 让队列堆积，max_depth=10000 防 OOM，aging 防 LOW 永久饿死
> 2. **未来扩展接口**：如果以后加 `handle_info({:im_push_batch, bins})` 批量入队路径
>    （比如服务端 batch_push 模式），这些阈值会立即生效
> 3. **API 完整性**：`OutboundQueue` 作为独立模块对外暴露 drain/enqueue API，
>    调用方可能不总是"1 入 1 drain"——单测里的连续 enqueue 20 条就是模拟这种用法

### 8.5 Bandit 层会堆积（但不是 OutboundQueue）

客户端慢、TCP 流控时，堆积发生在 **Bandit 层**，不在 OutboundQueue 层：

```
客户端慢 ← TCP 流控 ← Bandit socket write ← Bandit frames 队列 ← PacketTransport.drain ← OutboundQueue
                                          ↑
                                       这里堆积
                                    (TCP / Bandit 层)
```

`{:push, frames, state}` 返回后 frames 交给 Bandit，Bandit 在自己的 socket 发送缓冲区排队。
**OutboundQueue 已经 drain 清空了**——PacketTransport 不知道 Bandit 没发出去，继续处理下一条 push。

后果：

- Bandit frames 队列堆积 → 内存上涨 → Bandit 自己有上限或 OOM
- 客户端 90s 心跳超时（`idle_timeout_ms`）→ PacketTransport 关连接
- 关连接后，Bandit frames 队列丢弃，客户端靠 `CMD_SYNC_OFFLINE` 拉 inbox 补未读

### 8.6 一句话总结

> **按当前 push_via_queue "1 入 + 立即 drain(16)" 的工作模式，OutboundQueue 实际上不会堆积。**
> aging、coalesce_depth、max_depth 这些阈值在当前调用路径下永远不会触发，
> 它们是**防御性兜底 + 未来扩展接口**（万一未来加入批量入队路径立即生效）。
> 客户端慢导致的堆积发生在 Bandit frames 队列，不在 OutboundQueue。

---

## 九、设计意图 vs 实现 gap（已修复 G-40，2026-09-02 方案 B 周期 drain）

> §8 说"当前调用路径下不会堆积"，根因不是设计错了，而是**实现没有按设计的 drain 时机做**。
> 这一节对照 [设计文档 message-send-ack.md §7](../../design/message-send-ack.md#L209-L312) 与当前代码，
> 指出实现简化了"Socket 背压反馈"这一层，导致 WFQ 优先级实际不生效。
>
> **2026-09-02 修复（方案 B：周期 drain）**：Bandit WebSock 不暴露 socket 可写状态，无法严格按设计 §7.6
> 实现。采用周期 drain——`push_via_queue` 只入队不立即 drain，加 `:drain_tick` 周期触发
> `drain_outbound/1`。队列会堆积（周期内入队的多条消息），aging/coalesce/max_depth 全部生效，WFQ 多带
> 选择在多带同时积压时生效。客户端慢的堆积仍在 Bandit frames 队列层（Bandit 不暴露状态无法解决）。
>
> 测试：[packet_transport_test.exs](https://github.com/memacs/im/blob/main/apps/elixir/im/test/im_web/packet_transport_test.exs)
> 新增 10 个测试全绿，覆盖 push_via_queue 只入队、drain_tick 触发、max_burst 限制、WFQ 多带权重。

### 9.1 设计文档的预期堆积触发条件

[设计 §7.6](../../design/message-send-ack.md#L275-L282) 明确写：

| 场景 | 行为 |
| --- | --- |
| 队列空 + Socket 可写 + HIGH | 可**直写**（不入队） |
| **队列非空或 Socket 背压** | **一律入队，由调度器统一 drain** |
| depth > 32 | 合并 |
| depth > 10000 | 丢 LOW |

**设计意图**：当 Socket 写不出去（背压）时，新消息应该入队，让队列堆积，由 WFQ 调度统一 drain。
这是 aging/coalesce/max_depth 这些阈值预期触发的来源。

### 9.2 设计的 drain 时机 ⭐

[设计 §7 末尾 L312](../../design/message-send-ack.md#L312)：

> 实现落位：`IM.Delivery.OutboundQueue`（每连接进程或 Registry 托管），
> **由 `IM.Delivery.ConnectionManager` 在 Socket `{:tcp,:send}` 可写时 drain**。

设计模式：

```
1. push 来了 → 入队（不立即发）
2. 等 Socket 可写事件（{:tcp, :send} 可写）
3. Socket 可写 → drain 一批到 Socket
```

### 9.3 实现现状（gap 所在）

[packet_transport.ex push_via_queue L162-189](https://github.com/memacs/im/blob/main/apps/elixir/im/lib/im_web/packet_transport.ex#L162-L189)：

```elixir
defp push_via_queue(state, bin, meta) do
  if OutboundQueue.empty?(state.outbound) and
       OutboundQueue.normalize_priority(priority) == :high do
    {:push, {:binary, bin}, refresh_idle(state)}     # 直写
  else
    q = OutboundQueue.enqueue(state.outbound, item)
    {bins, q2} = OutboundQueue.drain(q, max_burst)   # ⚠️ 入队后立即 drain
    ...
    push_bins(bins, state)
  end
end
```

实现模式：

```
1. push 来了 → 入队 1 条
2. 立即 drain 16（不等 Socket 可写事件）
3. push bins 给 Bandit
```

### 9.4 Gap 对照表

| 维度 | 设计意图 | 当前实现 | 影响 |
| --- | --- | --- | --- |
| drain 时机 | Socket `{:tcp,:send}` 可写时 drain | 入队后立即 drain | **队列永远不会堆积** |
| 背压反馈 | Socket 背压时新消息一律入队 | 没有背压反馈机制 | 客户端慢时 OutboundQueue 不堆，堆在 Bandit frames 队列 |
| 队列深度触发 | depth>32 合并 / depth>10000 丢 LOW | 永远不会触发 | aging/coalesce/max_depth 在当前调用路径下是死代码 |
| WFQ 优先级生效条件 | 多带同时积压时按权重选带 | 队列始终为 0 或 1，select_band 永远没机会做多带选择 | **HIGH/NORMAL/LOW 在客户端慢时实际按 Bandit FIFO 发，不是 WFQ** |

### 9.5 根本原因

Bandit 的 `WebSock` behaviour **没有把 Socket 背压状态反馈给 PacketTransport**。
设计预期的 `IM.Delivery.ConnectionManager` 监听 `{:tcp,:send}` 可写事件这一层**根本没实现**——
PacketTransport 只是简单地"入队即发"。

### 9.6 这是 bug 还是设计简化？

**取决于视角**：

1. **"过简化"视角**：实现把"Socket 可写时 drain"简化成"入队即 drain"，**省掉了 Socket 背压状态跟踪**。
   好处是代码简单；坏处是设计预期的 WFQ 优先级机制**实际不生效**——
   因为队列始终为空，WFQ 永远没机会做多带选择。

2. **"够用"视角**：Bandit 自己有 frames 队列和反压管理，PacketTransport 把 bins push 给 Bandit 后
   Bandit 自己排队——**等价于把 WFQ 优先级调度让 Bandit 做了**。但 Bandit 不知道 priority，
   只按 FIFO 发，所以 **HIGH/NORMAL/LOW 在客户端慢时是按 FIFO 发的，不是按 WFQ**。

3. **"协议为准"视角**（AGENTS.md 硬约束）：实现违反了
   [AGENTS.md「协议为准」](../../../AGENTS.md#L154-L165)——
   设计文档 §7.6 明确写了 "Socket 背压时一律入队，由调度器统一 drain"，
   实现没做这层。**严格说这是个实现 gap，应记录到 [gap-review.md](gap-review.md)**。

### 9.7 修复方案（如果要按设计实现）

1. **Bandit 是否暴露 socket 可写状态**：需要查 Bandit/ThousandEyes WebSock 文档；
   如果不暴露，可能要绕过 WebSock 直接用 `:gen_tcp` 接收 `{tcp, socket, :io_busy}` 等消息
2. **push_via_queue 改成"只入队，不立即 drain"**：
   ```elixir
   defp push_via_queue(state, bin, meta) do
     # 高优先 + 队列空 + socket 可写 → 直写
     # 否则 → 只入队，等 :socket_writable 触发 drain
   end
   ```
3. **加 `handle_info(:socket_writable, state)`**：触发 drain(max_burst) 把队列冲刷到 socket
4. **保留现有 aging/coalesce/max_depth**：修复后立即生效，达到设计预期

### 9.8 不修也行？

**短期可以不修**，理由：

- 当前实现简单稳定，Bandit frames 队列足够支撑常见场景
- 真正会受影响的场景：**客户端慢 + HIGH/NORMAL/LOW 混合投递**——此时本应让 HIGH 先发，实际按 FIFO
- 如果目标用户网络都还 OK，这层 gap 不会暴露
- [设计文档 §7.6](../../design/message-send-ack.md#L275-L282) 的"Socket 背压时入队"
  本身是优化项，不是协议契约（不影响消息必达性，只影响优先级排序）

**长期建议修**：如果要真正落地"百万级在线 + WFQ 优先级调度"卖点（见 [项目一量化成果](../../../刘帆.md)），
应该按设计 §7 实现背压反馈，让 OutboundQueue 在客户端慢时真正发挥优先级调度作用。

### 9.9 残留 gap：Bandit 不暴露 socket 可写状态（G-40-RESIDUAL）

> **2026-09-02 方案 B 修复后的残留 gap**。周期 drain 已让 OutboundQueue 在应用层堆积 → aging/coalesce/
> max_depth/WFQ 全部生效，但**无法对齐设计 §7.6 的"Socket 背压时入队"语义**——根因是 Bandit WebSock
> 不暴露 socket 可写状态给 PacketTransport。

#### 9.9.1 残留 gap 定义

设计 §7.6 预期的 drain 时机是：

> **由 `IM.Delivery.ConnectionManager` 在 Socket `{:tcp,:send}` 可写时 drain**

但 Bandit 的 `WebSock` behaviour **没有把 socket 背压状态反馈给业务进程**——`{:push, frames, state}` 返回后，
frames 进入 Bandit 自己的 socket 发送缓冲区，PacketTransport **无法知道 Bandit 有没有真的发出去、
缓冲区有多满、TCP 流控是否触发**。

#### 9.9.2 影响范围

| 层级 | 修复后状态 | 是否对齐设计 |
| --- | --- | --- |
| OutboundQueue 应用层 | 周期 drain（50ms）让队列堆积，WFQ 多带权重生效 | ✅ |
| Bandit frames 队列层 | 客户端慢时仍堆积，**按 FIFO 发**（Bandit 不知道 priority） | ❌ 残留 gap |
| TCP / Socket 背压感知 | 无，PacketTransport 无法收 `{tcp, :io_busy}` 类事件 | ❌ 残留 gap |

**实际后果**：客户端慢 + HIGH/NORMAL/LOW 混合投递时，应用层 OutboundQueue 按 8/4/1 权重出队没问题；
但 drain 出来的 bins 进入 Bandit frames 队列后，Bandit 按 FIFO 发，**HIGH 不会真的先到客户端**——
应用层 WFQ 优先级在 Bandit frames 层被 FIFO 抹平。

#### 9.9.3 当前缓解措施（方案 B 已做的）

1. **周期 drain（50ms）**：让 OutboundQueue 在周期内堆积，触发 aging/coalesce/max_depth 全部生效
2. **WFQ 多带选择**：HIGH+NORMAL+LOW 同时积压时按 8/4/1 权重出队，应用层调度正确
3. **HIGH 队列空时直写快路径**：低负载下 ACK/踢人零延迟
4. **`outbound_max_depth=10000` + 丢最旧 LOW**：防应用层 OOM
5. **`idle_timeout_ms` 心跳超时**：客户端长期不消费 → PacketTransport 关连接，Bandit frames 队列丢弃，
   客户端重连后靠 `CMD_SYNC_OFFLINE` 拉 inbox 补未读

#### 9.9.4 长期解法（v1 不做）

| 方案 | 描述 | 成本 |
| --- | --- | --- |
| **A. 迁移到 ThousandIsland2** | Bandit 底层就是 ThousandIsland，ThousandIsland2 暴露 socket 可写回调；或绕过 Bandit 直接用 `:gen_tcp` 监听 `{:tcp, socket, :io_busy}` 类事件 | 重写传输层，v1 不做 |
| **B. 自实现 WebSocket** | 不依赖 Bandit WebSock，直接用 `:gen_tcp` + ws 帧编解码，完整控制 socket 背压 | 高成本，v1 不做 |
| **C. Bandit 上游 PR** | 给 Bandit 加 `handle_socket_writable/1` 回调，反馈给业务进程 | 依赖上游，时间不可控 |

**触发时机**：当 v2 目标用户出现"客户端慢 + 多带混合投递"场景且投诉 HIGH 没先到时，启动方案 A。
当前 v1 用户网络 OK，这层 gap 不会暴露。

#### 9.9.5 v1 接受理由

1. **周期 drain 已让应用层 WFQ 生效**：aging/coalesce/max_depth 不再是死代码，单测全绿
2. **Bandit FIFO 仅在客户端慢 + 多带混合投递时暴露**：常见场景下 OutboundQueue drain 出来的 bins
   Bandit 立即发完，FIFO 与 WFQ 等价
3. **不影响消息必达性**：残留 gap 只影响"客户端慢时的优先级排序"，不影响 ACK/未读/会话一致性
4. **已有兜底**：`idle_timeout_ms` 心跳超时 + `CMD_SYNC_OFFLINE` 重连补拉，客户端慢到极端时关连接重连

> **归档**：此残留 gap 已记录到 [gap-review.md §5.1 残留 gap（v1 接受）](gap-review.md#5-残留-gapv1-接受)，
> 编号 **G-40-RESIDUAL**，v2 启动前重新评估。

