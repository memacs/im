# Requirements — Review Debt Wave3

## 目标

对齐设计的权限热缓存、把 Outbound 优先级排序挂到真实投递、补全 im_client 管理命令、接入 Oban 替换 Task/GenServer MVP。

## 需求

### R1 权限缓存（DD-033）

1. `IM.Cache` 支持 SET（sadd/srem/sismember）与 ZSET（zadd/zrem/zscore）及 exists。
2. `BlockCache`：键 `im:block:{app}:{blocker}` 为 SET；冷 key 回源 PG 批量 SADD。
3. `MuteCache`：键 `im:mute:{app}:{group}` 为 ZSET，score=`muted_until` ms；群发路径走 MuteCache。
4. `DeviceBanCache`：键 `im:device_ban:{app}:{device_id}` STRING；登录/Token 校验优先热缓存。

### R2 Outbound WFQ

`FanoutBatcher.deliver_messages/3` 推送前按 `Outbound.sort_by_priority/1` 排序（priority 高→低，同级 inbox_seq）。

### R3 im_client 管理命令

Connection + `IM.Client` 门面补全：好友 accept/reject/delete/block/unblock、群 kick/invite/dismiss/set_admin、`ack_batch`、`msg_read`。

### R4 Oban

1. 依赖 Oban；迁移 `oban_jobs`；监督树挂载。
2. `GroupInboxFanout` / `MessageBurn` / `TtlPurge` 经 Oban Worker；保留对外 `enqueue`/`schedule`/`run_once` API。
3. 测试用 `testing: :inline`。

### 非目标

L1 ETS + PubSub 失效广播、完整每连接 WFQ GenServer、Kafka Consumer。
