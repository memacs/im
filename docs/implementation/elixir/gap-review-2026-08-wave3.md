# 全项目全面审核（第三轮，2026-08-04）

> 前置：[gap-review-2026-08.md](gap-review-2026-08.md) Phase 13 Remediation 已完成。  
> 本轮：在 PROGRESS 全 `done` 前提下，对照设计/实现/运维/CI 做 **生产就绪** 审查。

---

## 1. 结论摘要

| 维度 | 状态 |
|------|------|
| Phase 0–13 功能 | PROGRESS 全 `done`；proto `_REQ` 均已注册；apps 无 `TODO`/`FIXME` |
| im-console Coverage | 25/25「可演示」 |
| **生产就绪** | ⏳ 规模压测未归档；部分实现/文档/CI 仍有缺口（见 §2） |
| v1 deferred | FCM/APNs、Refresh Token、Kafka 本地栈、OpenTelemetry 全量等（§5） |

---

## 2. 发现项（按优先级）

### P0 — 生产门禁（验收/运维，非功能未写）

| ID | 问题 | 说明 |
|----|------|------|
| G-40 | 规模压测报告未归档 | LT-10/30/31/33、72h soak；见 `protocol-regression-checklist.md` |
| G-41 | 多节点须配 `REDIS_URL` | **done** | prod 启动 `Logger.warning`；K8s ConfigMap 已含 REDIS_URL |
| G-42 | 工作区大量变更未提交 | 缓存、Phase 13、provision、K8s、im-console 等 |

### P1 — 重要实现/工具链

| ID | 问题 | 说明 |
|----|------|------|
| G-50 | **单聊离线未入队 MobilePush** | P5-09 声明 Router 分流；实际仅 `GroupPusher` 调用；单聊 `msg_send` 只 `push_binary` |
| G-51 | `mobile-push.md` 实现文档超前 | 描述 `PushDisplay`/`flush_batch`/Redis 幂等；代码为 GenServer 队列 + `EventBus.Push` |
| G-52 | Event Bus 默认关闭 | `EVENT_BUS_ENABLED=false`；`im.push` 默认不出节点（旁路需显式开启） |
| G-53 | `mise run ci` ≠ GHA | 缺 `proto-gen-check`、`im_client:test`、`loadtest:test` |
| G-54 | `GroupPusher` 未传 `msg_id` | `MobilePush` 默认 `"unknown"` |

### P2 — 锦上添花

| ID | 问题 | 说明 |
|----|------|------|
| G-60 | im-console 未进 CI | `web:test`/`web:build` 仅 mise |
| G-61 | Release 冒烟未进 CI | **done** | `im:test-smoke` + GHA job 步骤 |
| G-62 | 后台 Cron 默认关 | `UNREAD_FLUSH_AUTO`、`PERMISSION_RECONCILE_AUTO`、`TTL_PURGE_AUTO`；K8s 未预置 |
| G-63 | im-console Payload GZIP | **done** | pako + AuthResp 协商 |
| G-64 | MSG_STREAM 无 Chat 专用 UI | **done** | Chat 四段流 |

### 文档漂移

| ID | 问题 |
|----|------|
| G-70 | `roadmap.md` Phase 11 完成定义仍 `- [ ]` |
| G-71 | `design-decisions.md` App Channel「待评审」 |
| G-72 | `.kiro/specs/phase-7/8` 仍写 P7-08/P8-09 deferred |
| G-73 | `PROGRESS` P12-05 写 BATCH 仅 Debug（Chat 已有 ACK_BATCH） |

---

## 3. Remediation 计划（本轮）

| ID | 动作 | 状态 |
|----|------|------|
| G-50 | `IM.Delivery.Router` 离线入队；`msg_send` 传 `msg_id`/`conv_id` | **done** |
| G-51 | 重写 `mobile-push.md` 实现文档为 v1 实际行为 + deferred 表 | **done** |
| G-53 | `mise ci` 对齐 GHA | **done** |
| G-54 | `GroupPusher` 传递 `msg_id`/`conv_id` | **done** |
| G-60 | GHA 增加 `im-console` job | **done** |
| G-62 | K8s ConfigMap 注释 + `deploy-guide` 说明 Cron env | **done** |
| G-70–73 | 文档同步 | **done** |
| G-61 | GHA `im:test-smoke` + mise 任务 | **done** |
| G-63–64 | im-console GZIP + MSG_STREAM Chat | **done** |
| G-41 | prod 无 REDIS_URL 启动告警 | **done** |

**仍 v1 deferred / 运维**：G-40 压测归档、G-42 提交、G-52 Kafka 本地栈、PushDisplay/Redis 推送幂等。

---

## 4. 修复记录（2026-08-04 第三轮）

| ID | 修复 |
|----|------|
| G-50 | `IM.Delivery.Router` 离线入队；`msg_send` 传 `msg_id`/`conv_id`；`router_test.exs` |
| G-51 | `docs/implementation/elixir/mobile-push.md` v1 对齐 |
| G-53 | `mise.toml` `[tasks.ci]` 含 proto-gen-check、im_client、loadtest |
| G-54 | `GroupPusher.push/4` 传递 `msg_id`/`conv_id` |
| G-60 | `.github/workflows/ci.yml` `web-console` job |
| G-62 | `configmap.yaml` Cron 注释 + `deploy-guide.md` §6–§7 |
| G-70–73 | roadmap Phase 11、design-decisions、Kiro specs、PROGRESS P5-09/P12-05 |

**仍待运维/环境**：G-40 规模压测归档、G-42 git 提交、G-52 Kafka 本地栈。

### 3.3 第四轮收尾（2026-08-04 续）

| ID | 修复 |
|----|------|
| G-61 | `im:test-smoke` + GHA `Release 冒烟（进程内）` 步骤 |
| G-63 | im-console `compression.ts` + pako；`encodePacket`/`decodePacket` 协商 GZIP |
| G-64 | Chat `MSG_STREAM` 四段发送；Coverage 更新 |
| G-41 | `IM.Application.warn_redis_cache!/0` prod 启动告警 |

### 3.2 Postgres 端口误判（2026-08-04）

| ID | 修复 |
|----|------|
| G-80 | `resolve-pg-port.sh` + mise 任务自动 PGPORT；[`local-dev-gotchas.md`](local-dev-gotchas.md)；`agent.md` / im-implementation 技能 |

---

## 5. v1 刻意不做

与 [gap-review-2026-08.md §5](gap-review-2026-08.md) 一致，另加：

- FCM/APNs SDK（外置推送服务消费 `im.push`）
- `IM.Delivery.PushDisplay`、推送 Redis 幂等（设计有、v1 简化）
- Java 实现占位
- 万连/大群 P99/72h **环境实测归档**

---

## 6. 相关文档

- [PROGRESS.md](PROGRESS.md)
- [protocol-regression-checklist.md](protocol-regression-checklist.md)
- [deploy-guide.md](deploy-guide.md)
- [mobile-push.md](mobile-push.md)（实现）
