# Requirements — Review Debt Wave4

## 目标

补齐权限缓存 L1（ETS + PubSub 失效）与每连接出站 WFQ 队列（P3-09 完整调度）。

## 需求

### R1 权限 L1

1. `IM.Permission.L1`：进程内 ETS，短 TTL（默认 10s）。
2. Block / Mute / DeviceBan 读路径：L1 → L2(Cache) → PG；命中 L2/PG 后回填 L1。
3. `IM.Permission.Invalidator`：订阅 `im:permission:invalidate`，清本节点 L1。
4. 写穿（put/delete）后 `Invalidator.broadcast/1`。

### R2 OutboundQueue

1. `IM.Delivery.OutboundQueue`：三带 WFQ + aging + max_burst + max_depth 丢 LOW。
2. `PacketTransport` 持有队列；`{:im_push, bin | {bin, meta}}` 入队并 drain。
3. 队列空且可写时可直写（降低延迟）。
4. Router / FanoutBatcher 传递 `priority` / `inbox_seq`。

### 非目标

PUSH_BATCH 同带合并（coalesce）、每连接独立 GenServer、权限对账 Oban。
