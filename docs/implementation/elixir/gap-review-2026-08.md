# 全项目差距审查与Remediation（2026-08）

> 审查日期：2026-08-04  
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

## 3. 修复记录（2026-08-04）

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

### 3.1 第二轮收尾（2026-08-04 续）

| ID | 修复 |
|----|------|
| G-20 | `docs/implementation/README.md`、`product-overview.md`、elixir README Phase 表 |
| G-21 | `docs/design/friend.md` P8-09 → `require_friend_to_send` 已实现 |
| G-15 | `release-smoke-auth.sh` + `mise run release-smoke-auth` |
| G-30 | Debug AuthResp 全字段；Chat `CMD_MSG_ACK_BATCH_UP`；AuthReq 协商 compression |
| 测试 | `smoke_test.exs` 增加 `auth/0` |

---

## 4. 仍待环境实测（工具已就绪）

| 目标 | 场景/文档 |
|------|-----------|
| 单节点 3–5 万连接 | LT-10 `connection_load` |
| 大群扇出 P99 < 200ms | LT-30 `group_fanout` |
| 10 万 Channel 订阅 | LT-31 |
| 未读热路径规模 | LT-33 `unread_bump` |
| 72h soak | `loadtest-stability.md` |

将 `reports/*.json` 与环境说明归档至发布记录。

---

## 5. v1 刻意不做

见 `roadmap.md` deferred 表：Refresh Token、Elasticsearch、Payload GZIP 算法、推送 token 失效回调、聊天室离线历史等。

---

## 6. 相关文档

- [PROGRESS.md](PROGRESS.md) — Phase 13 任务看板
- [loadtest-report.md](loadtest-report.md) — LT-33 与 Job 说明
- [release-smoke-messaging.md](release-smoke-messaging.md)
- [release-smoke-auth.md](release-smoke-auth.md)
- [gap-review-2026-08-wave3.md](gap-review-2026-08-wave3.md) — 第三轮全面审核（生产就绪）
- [local-dev-gotchas.md](local-dev-gotchas.md) — **OrbStack Postgres 端口 / mix test 踩坑**
