# 第三方交付手册

面向 **接手部署、集成、验收** 的 IM 系统交付物说明。协议与设计以 `proto/` + [protocol.md](design/protocol/protocol.md) 为准；能力边界见 [KNOWN-LIMITATIONS.md](KNOWN-LIMITATIONS.md)。

---

## 1. 交付范围

### 1.1 包含

| 类别 | 路径 | 说明 |
| --- | --- | --- |
| 协议定义 | `proto/` | Protobuf 3，WebSocket 二进制帧 |
| 设计文档 | `docs/design/` | 架构、协议、各模块设计（语言无关） |
| 实现文档 | `docs/implementation/` | Elixir 实现、HTTP API、部署指南 |
| **可运行服务端** | `apps/elixir/im/` | Phase 0–13，Release 可构建 |
| 参考客户端 | `apps/elixir/im_client/` | 协议联调 / 压测用，**非**生产 SDK |
| 压测工具 | `apps/elixir/loadtest/` | 连接 / 消息压测 Job |
| Web 演示控制台 | `apps/web/im-console/` | 联调演示，**非**生产 Web SDK |
| 部署清单 | `deploy/elixir/im/` | Dockerfile + K8s Kustomize |
| CI | `.github/workflows/ci.yml` | proto / Elixir / Release 镜像 |
| 许可证 | [LICENSE](../LICENSE) | Apache License 2.0 |

### 1.2 不包含（v1）

- 生产 iOS / Android / Web SDK（须按 `proto/` 自行实现）
- FCM / APNs 真推送（Kafka `im.push` 事件可对接自建服务）
- Refresh Token（过期后重新 HTTP 登录）
- Java 服务端实现（目录为预留）
- 托管 PG / Redis / Kafka（须自备或使用云厂商托管）

详见 [KNOWN-LIMITATIONS.md](KNOWN-LIMITATIONS.md)。

---

## 2. 环境要求

### 2.1 开发 / 验收机

| 工具 | 版本 / 说明 |
| --- | --- |
| [mise](https://mise.jdx.dev/) | 锁定 Erlang / Elixir / protoc（见根 `mise.toml`） |
| Docker | 构建 Release 镜像 |
| kubectl + K8s | 本地 OrbStack / 目标生产集群 |
| PostgreSQL 15+ | 业务持久化 |
| Redis 7+ | 多副本 **必须**；缓存、序列号、在线状态 |

### 2.2 生产运行时（必填环境变量）

来自 `apps/elixir/im/config/runtime.exs`：

| 变量 | 说明 |
| --- | --- |
| `DATABASE_URL` | Ecto 连接串（含密码，放 Secret） |
| `SECRET_KEY_BASE` | Phoenix 密钥，≥ 64 字符（Secret） |
| `PHX_HOST` | 对外域名（Ingress Host） |
| `PHX_SERVER` | `true` |
| `PHX_SCHEME` | 生产建议 `https` |
| `REDIS_URL` | 多副本集群 **必填** |
| `RELEASE_COOKIE` | 多副本 libcluster 必填（Secret） |
| `RELEASE_NODE_MODE` | 多副本设 `pod_ip` |
| `CLUSTER_STRATEGY` | 多副本设 `kubernetes` |

完整列表见 [deploy-guide.md](implementation/elixir/deploy-guide.md) 与 [overlays/prod/README.md](../deploy/elixir/im/k8s/overlays/prod/README.md)。

---

## 3. 快速验收（接手后 30 分钟）

在仓库根目录执行：

```bash
mise install
mise run ci                    # proto + Elixir 测试 + 格式
mise run k8s-up                # 本地依赖栈
mise run release-deploy        # Release 镜像 + overlays/local
mise run k8s-port-forward      # 另开终端 → localhost:4000
mise run release-smoke           # /health/live + /health/ready
mise run im:test-smoke           # 进程内 messaging + auth
```

**通过标准**：上述命令均无失败退出码；`GET /health/ready` 返回 200。

---

## 4. 生产部署流程

### 4.1 构建镜像

```bash
docker build -f deploy/elixir/im/Dockerfile -t <registry>/im:v0.1.0 .
docker push <registry>/im:v0.1.0
```

### 4.2 外部依赖

1. **PostgreSQL**：创建库与用户，执行迁移（Release 启动前 `bin/im eval "IM.Release.migrate"` 或 Job）
2. **Redis**：独立实例或托管服务，记录连接 URL
3. **（可选）Kafka**：Event Bus 旁路，见 [deploy-guide.md §6](implementation/elixir/deploy-guide.md)

### 4.3 创建 Secret

**禁止**使用 `im-dev` 占位 Secret。参考模板：

```bash
kubectl create namespace im-prod
kubectl create secret generic im-runtime -n im-prod \
  --from-literal=SECRET_KEY_BASE="$(openssl rand -base64 64 | tr -d '\n')" \
  --from-literal=RELEASE_COOKIE="$(openssl rand -hex 16)" \
  --from-literal=DATABASE_URL="ecto://USER:PASS@pg-host:5432/im_prod"
```

模板文件：[secret.example.yaml](../deploy/elixir/im/k8s/overlays/prod/secret.example.yaml)

### 4.4 应用 prod overlay

```bash
# 编辑 overlays/prod/kustomization.yaml 中的 images.newName / newTag
# 编辑 overlays/prod/configmap-prod.yaml 中的 PHX_HOST、REDIS_URL
kubectl apply -k deploy/elixir/im/k8s/overlays/prod/
kubectl -n im-prod rollout status deployment/im
```

详见 [overlays/prod/README.md](../deploy/elixir/im/k8s/overlays/prod/README.md)。

### 4.5 上线前检查

- [ ] Secret 已外部注入，无 dev 占位值
- [ ] `DATABASE_URL` 连通，迁移已执行
- [ ] `REDIS_URL` 可达（多副本）
- [ ] Ingress TLS 已配置
- [ ] `/health/ready`、`/metrics` 可达
- [ ] `/internal/v1` 仅内网可达（NetworkPolicy / 网关）
- [ ] `mise run ci` 在交付版本上通过

---

## 5. 租户与用户 Bootstrap

IM 按 **`app_key`** 多租户隔离。v1 无独立「开租户」管理台，常用方式：

### 5.1 内部 Provision API（推荐联调 / 压测）

```bash
curl -X POST "https://<host>/internal/v1/users/<user_id>/provision" \
  -H "Content-Type: application/json" \
  -H "X-IM-Caller-Service: bootstrap" \
  -d '{"app_key":"your_app","password":"your_password"}'
```

> **生产**：`/internal/v1` 须内网隔离 + 调用方鉴权；勿暴露到公网。

### 5.2 HTTP 登录

```bash
curl -X POST "https://<host>/api/v1/sessions" \
  -H "Content-Type: application/json" \
  -d '{"app_key":"your_app","user_id":"u1","password":"your_password"}'
```

返回 `access_token`，用于 WebSocket 鉴权与 REST `Authorization: Bearer`。

接口详情：[http-api-reference.md](implementation/elixir/http-api-reference.md)

### 5.3 冒烟默认租户

本地 K8s 冒烟脚本默认 `app_demo`；**生产须替换为自有 `app_key`**。

---

## 6. 客户端集成

1. 阅读 [protocol.md](design/protocol/protocol.md) 与 `proto/`
2. 用 `protoc` 生成目标语言代码（见根 [README.md](../README.md) §生成代码）
3. WebSocket 连接 → Auth 包 → 业务 Cmd
4. REST 与 WS 双通道语义一致，见 [module-map.md](module-map.md)

参考实现：`apps/elixir/im_client/`（Elixir，非 SDK 承诺）。

---

## 7. 文档导航

| 角色 | 首读 |
| --- | --- |
| 产品 / 决策 | [product-overview.md](product-overview.md) |
| 后端开发 | [module-map.md](module-map.md) → [implementation/elixir/](implementation/elixir/) |
| 运维 | [deploy-guide.md](implementation/elixir/deploy-guide.md) → [deploy/README.md](../deploy/README.md) |
| REST 对接 | [http-api-reference.md](implementation/elixir/http-api-reference.md) |
| 能力边界 | [KNOWN-LIMITATIONS.md](KNOWN-LIMITATIONS.md) |
| 版本变更 | [CHANGELOG.md](../CHANGELOG.md) |

总索引：[docs/README.md](README.md)

---

## 8. 运维要点

| 项 | 说明 |
| --- | --- |
| 健康检查 | `/health/live`（存活）vs `/health/ready`（含 DB） |
| 指标 | `GET /metrics`（Prometheus） |
| CPU 火焰图 | `mise run flamegraph`（Erlang 原生 perf，须 `IM_PERF_FLAMEGRAPH=true`）→ [flamegraph.md](implementation/elixir/flamegraph.md) |
| 日志 | JSON 结构化，含 `trace_id` |
| 滚动发布 | `maxUnavailable: 0`，`terminationGracePeriodSeconds: 60` |
| PG 备份 | **交付方自备** runbook（本仓库未含） |
| Oban Cron | 未读刷盘、权限对账、TTL 清理——按需开启，见 [deploy-guide.md §7](implementation/elixir/deploy-guide.md) |

故障演练：[fault-drill.md](implementation/elixir/fault-drill.md)

---

## 9. 支持与变更

- **协议变更**：须同步 `proto/`、`docs/design/protocol/`、`docs/design-decisions.md`
- **Issue / 版本**：见 [CHANGELOG.md](../CHANGELOG.md)；交付方自行维护 fork 的 tag 与 release
- **许可证**：Apache 2.0，见 [LICENSE](../LICENSE)

---

## 相关链接

- [已知限制清单](KNOWN-LIMITATIONS.md)
- [生产 overlay](../deploy/elixir/im/k8s/overlays/prod/)
- [Release 验收](implementation/elixir/release-deploy-test.md)
- [差距审查](implementation/elixir/gap-review.md)
