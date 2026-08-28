# Requirements: Phase 10 压测与上线准备

| 项 | 内容 |
| --- | --- |
| Spec | `phase-10-loadtest-ops` |
| Roadmap | P10-01 ~ P10-05；loadtest LT-01~12、LT-20/21 |
| 依赖 | Phase 9；im_client IC-04+ |
| 状态 | 实施中 |

---

## Introduction

独立压测服务 `apps/elixir/loadtest`（仅 path 依赖 `im_client`），提供连接压测与消息 QPS 场景、JSON 报告、K8s Job 部署骨架，并补齐部署指南、故障演练与 protocol 回归 checklist。

---

## User Stories

### US-1：压测编排（P10-01 / L0–L1）

**作为** 运维/QA，**我想** 用 CLI 对 `svc/im`（或本地 URL）发起连接与消息压测，**以便** 得到可重复的延迟与成功率报告。

#### Acceptance Criteria

1. WHEN `mix compile`（loadtest），THE SYSTEM SHALL 通过，且依赖含 `{:im_client, path: ...}`、**不含** `:im`。
2. WHEN 运行 `connection_load`，THE SYSTEM SHALL 按配置并发建连+AUTH，输出 JSON（成功率、连接延迟分位数、错误分布）。
3. WHEN 运行 `message_flood`，THE SYSTEM SHALL 在已鉴权连接上发单聊消息并统计 ACK 延迟 / QPS。
4. THE SYSTEM SHALL 提供 Mix Task / CLI 入口便于本地与 Job 调用。

### US-2：部署与文档（P10-03~05、L2）

1. THE SYSTEM SHALL 提供 `deploy/elixir/loadtest/Dockerfile` 与 `k8s/job.yaml` 骨架。
2. THE SYSTEM SHALL 提供部署指南（Release + OrbStack/K8s）。
3. THE SYSTEM SHALL 文档化节点宕机 / Redis 超时预期行为。
4. THE SYSTEM SHALL 提供 protocol 主路径回归 checklist。
