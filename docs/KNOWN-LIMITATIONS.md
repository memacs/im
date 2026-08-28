# 已知限制清单（v1）

面向第三方集成与私有化部署的 **能力边界** 一览。协议与设计以 `proto/` + [protocol.md](design/protocol/protocol.md) 为准；实现进度见 [PROGRESS.md](implementation/elixir/PROGRESS.md)。

> **版本**：与仓库当前主分支对齐（Phase 0–13 完成）。规模压测归档见 [loadtest-report.md](implementation/elixir/loadtest-report.md)。

---

## 1. 生产就绪度

| 项 | 状态 | 说明 |
| --- | --- | --- |
| 核心 IM 协议能力 | ✅ 已实现 | 单聊/群/室、ACK、离线、扩展命令、App Channel 等 |
| 本地 / 联调 K8s | ✅ 可用 | `overlays/local`、`overlays/cluster` |
| **生产 overlay 模板** | 📋 模板交付 | [overlays/prod](../deploy/elixir/im/k8s/overlays/prod/) — 须替换镜像、Secret、外部 PG/Redis |
| 规模压测正式报告 | ⏳ 待归档 | 工具就绪（loadtest）；万连/大群/72h 需目标环境实测 |
| 移动推送（FCM/APNs） | ❌ v1 未接 | Kafka `im.push` 旁路已写；真推送 SDK 未集成 |
| Refresh Token | ❌ v1 未做 | Token 过期后须重新 `POST /api/v1/sessions` |
| Java 服务端 | ❌ 预留 | 仅 Elixir 实现可运行 |

---

## 2. 功能 deferred（v1 刻意不做）

| 能力 | 状态 | 替代 / 说明 |
| --- | --- | --- |
| Refresh Token / 连接内续期 | deferred | 重新 HTTP 登录；见 [auth.md](design/auth.md) §9.5 |
| FCM / APNs 真推送 | deferred | `im.push` Kafka 事件可对接自建推送服务 |
| OpenTelemetry 全量导出 | deferred | Prometheus `/metrics` + JSON 日志可用 |
| Elasticsearch 消息检索 | deferred | PostgreSQL 收件箱 + 离线拉取 |
| Payload GZIP 算法实现 | deferred | 压缩协商设计已确认（DD-034），算法待补 |
| 推送 token 失效回调 | deferred | — |
| 聊天室离线历史 | deferred | 聊天室默认不落库，设计如此 |
| Kafka 进默认依赖栈 | optional | 使用 `overlays/kafka-event-bus` 联调 |

完整 defer 表见 [roadmap.md](implementation/elixir/roadmap.md) 与 [gap-review.md](implementation/elixir/gap-review.md) §5。

---

## 3. 客户端与 SDK

| 项 | 状态 | 说明 |
| --- | --- | --- |
| 生产 iOS / Android SDK | ❌ 未包含 | 第三方用 `proto/` 自行生成 + 按 [protocol.md](design/protocol/protocol.md) 实现 |
| 参考客户端 | ✅ | `apps/elixir/im_client`（Elixir，测试/压测用） |
| Web 演示控制台 | ✅ | `apps/web/im-console` — **演示/联调**，非生产 Web SDK |
| 多语言 `gen/` 生成物 | ❌ 不入库 | 见根 [README.md](../README.md) §生成代码，自行 `protoc` |

---

## 4. 部署与运维

| 项 | 状态 | 说明 |
| --- | --- | --- |
| 托管 PostgreSQL / Redis | 须自备 | prod overlay **不含** 集群内 PG/Redis |
| 生产 Secret | 须外部注入 | 禁止使用 `im-dev` 占位 Secret |
| `/internal/v1` 鉴权 | 弱信任头 | 生产须 **内网隔离** + NetworkPolicy + 网关/mTLS |
| im-console 官方 Helm | ❌ | 静态 `dist/` + Ingress 反代，见 [web-console README](../apps/web/im-console/README.md) |
| PG 备份 / 灾备 runbook | 📋 待扩展 | 见 [DELIVERY.md](DELIVERY.md) §运维 |
| Helm Chart | ❌ | 当前仅 Kustomize |

---

## 5. 文档与内部资产

| 路径 | 第三方是否必读 |
| --- | --- |
| `docs/`、`proto/`、`deploy/` | **必读** |
| [http-api-reference.md](implementation/elixir/http-api-reference.md) | REST 对接必读 |
| `.kiro/specs/` | 可选（AI 开发过程记录，非行为契约） |
| `agent.md`、`.agents/skills/` | 可选（内部开发约定） |

---

## 6. 验收建议（第三方接手）

最低验收：

```bash
mise install
mise run ci
mise run release-deploy
mise run release-smoke
mise run im:test-smoke
```

生产前另须：替换 Secret、外部 PG/Redis 连通、`/health/ready` 与 `/metrics` 可达。详见 [DELIVERY.md](DELIVERY.md)。

---

## 相关链接

- [交付手册](DELIVERY.md)
- [产品介绍](product-overview.md)
- [部署指南](implementation/elixir/deploy-guide.md)
- [差距审查](implementation/elixir/gap-review.md)
