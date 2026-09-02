# 全项目差距审查与 Remediation

> 范围：`apps/elixir/im`、`im_client`、`loadtest`、`im-console`、`deploy/`、设计/实现文档  
> 状态：**Remediation 已落地**（见下文「修复记录」）

---

## 1. 审查结论摘要

| 维度 | 审查前 | Remediation 后 |
|------|--------|----------------|
| 核心协议 Phase 0–12 | PROGRESS 标 100% | 不变；补录 Phase 13 |
| 用户 bootstrap | 压测/部署须手工 seed | `POST /internal/v1/users/:id/provision` + loadtest `UserBootstrap` |
| 未读/缓存/会话 API | 已实现未进 PROGRESS | Phase 13 已登记 |
| K8s 运维 | 无 NetworkPolicy/HPA、Job 命名空间错误 | 已补 YAML |
| im-console | 无会话 REST/未读 UI | Chat 页已对接 |
| 文档 | README/协议仍写 Phase 0、deferred | **已同步**（含 friend.md P8-09、implementation 索引） |

**仍属 v1 刻意 deferred（未在本轮实现）**：FCM/APNs 真推送、Kafka 进本地依赖栈、Refresh Token、OpenTelemetry 全量、万连/大群/72h 规模实测归档。

---

## 2. 发现项清单（审查原始）

### 2.1 生产前关键

| ID | 问题 | 优先级 |
|----|------|--------|
| G-01 | 无用户 provisioning，压测 login 401 | P0 |
| G-02 | loadtest K8s Job `namespace`/`APP_KEY` 错误 | P0 |
| G-03 | NetworkPolicy / HPA 缺失 | P0 |
| G-04 | 移动推送未接 FCM/APNs | P1（deferred v1） |
| G-05 | Kafka 默认栈未部署 | P1（旁路可选） |

### 2.2 功能/实现

| ID | 问题 | 优先级 |
|----|------|--------|
| G-10 | 未读热路径 + UnreadFlush + 会话 REST 未进 PROGRESS | P1 |
| G-11 | 群/室/好友/Token 缓存未进 PROGRESS | P1 |
| G-12 | Permission Reconciler 未覆盖群成员/好友缓存 | P1 |
| G-13 | loadtest 场景无自动建用户 | P0 |
| G-14 | LT-33 `unread_bump` 无 K8s Job | P2 |
| G-15 | AUTH 冒烟无 CronJob | P2 |

### 2.3 文档漂移

| ID | 问题 |
|----|------|
| G-20 | 根 README / elixir README 仍写 Phase 0 |
| G-21 | protocol/friend 仍标 P8-09、MSG_STREAM deferred |
| G-22 | loadtest-report 未收录 unread_bump |
| G-23 | K8s README PDB「尚未做」与 cluster overlay 矛盾 |
| G-24 | Kiro tasks 与 PROGRESS 不一致 |

### 2.4 im-console

| ID | 问题 |
|----|------|
| G-30 | 无 GET /conversations、未读角标 |
| G-31 | Coverage 矩阵缺会话 REST |

---

## 3. 修复记录

| ID | 修复 |
|----|------|
| G-01 | `IM.Services.User.provision/1`；`POST /internal/v1/users/:user_id/provision` |
| G-02 | `deploy/elixir/loadtest/k8s/job.yaml` → `im-dev`、`app_demo` |
| G-03 | `networkpolicy.yaml`；`overlays/cluster/hpa.yaml` |
| G-10–11 | PROGRESS Phase 13 |
| G-12 | `Permission.Reconciler` 增加 `group_member` / `friendship` |
| G-13 | `IM.LoadTest.UserBootstrap`；Worker/各场景接入 |
| G-14 | Job 默认场景 `unread_bump`；`run_loadtest` 多场景分发 |
| G-15 | `cronjob-smoke-auth.yaml` + `bin/smoke-auth` + `IM.Release.Smoke.auth/0` |
| G-20–24 | README、loadtest-report、Kiro tasks、K8s README 更新 |
| G-30–31 | im-console `listConversations` + Chat 会话面板 + Coverage |

### 3.1 第二轮收尾

| ID | 修复 |
|----|------|
| G-20 | `docs/implementation/README.md`、`product-overview.md`、elixir README Phase 表 |
| G-21 | `docs/design/friend.md` P8-09 → `require_friend_to_send` 已实现 |
| G-15 | `release-smoke-auth.sh` + `mise run release-smoke-auth` |
| G-30 | Debug AuthResp 全字段；Chat `CMD_MSG_ACK_BATCH_UP`；AuthReq 协商 compression |
| 测试 | `smoke_test.exs` 增加 `auth/0` |

### 3.2 第三轮：出站调度 WFQ gap 修复（2026-09-02）

| ID | 修复 |
|----|------|
| G-40 | 出站调度周期 drain 实现：`PacketTransport.push_via_queue` 改为只入队不立即 drain；`init/1` 加 `:drain_tick` 周期触发（默认 50ms）；提取 `drain_outbound/1` 公共函数。队列在周期内堆积 → aging/coalesce/`outbound_max_depth` 全部生效；WFQ 多带选择在多带同时积压时按 8/4/1 权重出队。新增 `packet_transport_test.exs` 10 个测试全绿，覆盖入队不 drain、`drain_tick` 触发、`max_burst` 限制、HIGH+NORMAL+LOW WFQ 权重。详见 [`outbound-queue-scheduling.md` §九](outbound-queue-scheduling.md)。 |

---

## 4. 仍待环境实测（工具已就绪）

| 目标 | 场景/文档 |
|------|-----------|
| 单节点 3–5 万连接 | LT-10 `connection_load` |
| 大群扇出 P99 < 200ms | LT-30 `group_fanout` |
| 10 万 Channel 订阅 | LT-31 |
| 未读热路径规模 | LT-33 `unread_bump` |
| 72h soak | `loadtest-stability.md` |
| **WFQ 优先级实测**（G-40 已代码修复，待实测） | 慢客户端 + HIGH/NORMAL/LOW 混合投递，验证周期 drain（50ms）下 HIGH 是否按 8/4/1 权重先到；Bandit 不暴露 socket 可写状态，客户端慢的最终堆积仍在 Bandit frames 层 |

将 `reports/*.json` 与环境说明归档至发布记录。

---

## 5. 残留 gap（v1 接受）

> G-40 方案 B 周期 drain 修复后**仍无法对齐设计 §7.6 的残留 gap**，v1 接受，v2 启动前重新评估。

### 5.1 G-40-RESIDUAL：Bandit 不暴露 socket 可写状态

| 维度 | 内容 |
|------|------|
| **ID** | G-40-RESIDUAL |
| **来源** | G-40 方案 B 周期 drain 修复后的残留限制 |
| **现象** | Bandit `WebSock` behaviour 不把 socket 背压状态反馈给 PacketTransport，`{:push, frames, state}` 返回后 frames 进入 Bandit 自己的 socket 发送缓冲区，PacketTransport 无法知道 Bandit 是否真的发出去、缓冲区多满、TCP 流控是否触发 |
| **设计预期** | 设计 §7.6 预期"由 `IM.Delivery.ConnectionManager` 在 Socket `{:tcp,:send}` 可写时 drain"——PacketTransport 应能感知 socket 可写事件 |
| **影响范围** | OutboundQueue 应用层 ✅ 周期 drain 让队列堆积，WFQ 多带权重生效；<br>Bandit frames 队列层 ❌ 客户端慢时仍堆积，**按 FIFO 发**（Bandit 不知道 priority）；<br>TCP / Socket 背压感知 ❌ 无，PacketTransport 无法收 `{tcp, :io_busy}` 类事件 |
| **实际后果** | 客户端慢 + HIGH/NORMAL/LOW 混合投递时，应用层 OutboundQueue 按 8/4/1 权重出队，但 drain 出来的 bins 进入 Bandit frames 队列后 Bandit 按 FIFO 发，**HIGH 不会真的先到客户端**——应用层 WFQ 优先级在 Bandit frames 层被 FIFO 抹平 |
| **当前缓解（方案 B 已做的）** | ① 周期 drain（50ms）让队列堆积，aging/coalesce/max_depth 全部生效；② WFQ 多带选择按 8/4/1 权重出队；③ HIGH 队列空时直写快路径；④ `outbound_max_depth=10000` + 丢最旧 LOW 防 OOM；⑤ `idle_timeout_ms` 心跳超时关连接 + `CMD_SYNC_OFFLINE` 重连补拉 |
| **长期解法（v1 不做）** | A. 迁移到 ThousandIsland2（暴露 socket 可写回调）/绕过 Bandit 直接用 `:gen_tcp` 监听 `{tcp, :io_busy}`；B. 自实现 WebSocket（直接 `:gen_tcp` + ws 帧编解码）；C. 给 Bandit 上游 PR 加 `handle_socket_writable/1` 回调 |
| **v1 接受理由** | ① 周期 drain 已让应用层 WFQ 生效，单测全绿；② Bandit FIFO 仅在客户端慢 + 多带混合投递时暴露，常见场景下 FIFO 与 WFQ 等价；③ 不影响消息必达性（只影响客户端慢时的优先级排序）；④ 已有兜底（心跳超时 + 重连补拉） |
| **触发时机** | v2 目标用户出现"客户端慢 + 多带混合投递"场景且投诉 HIGH 没先到时，启动方案 A |
| **详细分析** | [`outbound-queue-scheduling.md` §9.9](outbound-queue-scheduling.md#99-残留-gapbandit-不暴露-socket-可写状态g-40-residual) |

---

## 6. v1 刻意不做

见 `roadmap.md` deferred 表：Refresh Token、Elasticsearch、Payload GZIP 算法、推送 token 失效回调、聊天室离线历史等。

---

## 7. 相关文档

- [PROGRESS.md](PROGRESS.md) — Phase 13 任务看板
- [loadtest-report.md](loadtest-report.md) — LT-33 与 Job 说明
- [release-smoke-messaging.md](release-smoke-messaging.md)
- [release-smoke-auth.md](release-smoke-auth.md)
- [outbound-queue-scheduling.md](outbound-queue-scheduling.md) — 出站 WFQ 调度详解（含 §9 G-40 修复与 §9.9 残留 gap）
- [gap-review-wave3.md](gap-review-wave3.md) — 第三轮全面审核（生产就绪）
- [local-dev-gotchas.md](local-dev-gotchas.md) — **OrbStack Postgres 端口 / mix test 踩坑**
