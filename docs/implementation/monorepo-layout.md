# 单仓多实现目录布局

| 项 | 内容 |
|------|------|
| 状态 | **已确认** |
| 关联 | [project-structure.md](elixir/project-structure.md)（IM 服务 `lib/` 细节）、[roadmap.md](elixir/roadmap.md) P0-01 |

> **原则**：仓库根只放 **协议 + 文档 + 工具配置**；所有可编译、可部署的实现放在 `apps/`；部署清单与 `apps/` 一一对应放在 `deploy/`。

---

## 总览

```text
im/
├── proto/                         # 语言无关协议（唯一真相）
├── docs/                          # design + implementation 文档
├── AGENTS.md                      # AI 协作约定（Cursor / Copilot 等可读）
├── mise.toml                      # 工具版本；mix 任务指向 apps/elixir/im
│
├── apps/                          # ★ 可运行实现
│   ├── elixir/
│   │   ├── im/
│   │   ├── loadtest/
│   │   └── im_client/
│   ├── java/
│   │   └── im/
│   └── web/
│       └── im-console/            # Web 演示控制台（独立 SPA，DD-037）
│
└── deploy/
    ├── elixir/
    │   ├── im/
    │   └── loadtest/
    ├── web/
    │   └── im-console/            # 可选：静态站镜像（dev/staging）
    └── java/
        └── im/
```

---

## 分层职责

| 路径 | 职责 | 不上生产 |
|------|------|----------|
| `apps/elixir/im` | WS、REST、Dispatch、Services、Delivery、Ecto | — |
| `apps/elixir/loadtest` | 连接/消息压测、场景编排、指标上报 | 与 IM Deployment 分离 |
| `apps/elixir/im_client` | Packet 编解码、WS 客户端（供 test + loadtest） | 非 OTP 发布物 |
| `apps/web/im-console` | 浏览器演示/联调 SPA（TypeScript + Vite + React） | 独立静态部署，不进 IM Release |
| `apps/java/im` | Java 版 IM | — |

**主 IM 与压测必须分 Mix 项目**：Release 镜像、依赖、K8s 工作负载类型不同。

---

## Elixir：兄弟项目（非 Umbrella）

```text
apps/elixir/
├── im/mix.exs
├── loadtest/mix.exs          # {:im_client, path: "../im_client"}
└── im_client/mix.exs         # Phase 2+ 从 im/test 抽出
```

`loadtest` **不得** `path:` 依赖整个 `im` 应用（避免 Ecto/Kafka 进压测镜像）。

---

## 部署与构建

| 应用 | Dockerfile | K8s | 构建上下文 |
|------|------------|-----|------------|
| IM | `deploy/elixir/im/Dockerfile` | `deploy/elixir/im/k8s/` | **仓库根** `.` |
| Loadtest | `deploy/elixir/loadtest/Dockerfile`（Phase 10） | Job / CronJob | 仓库根 |

```bash
# IM Release 镜像（context = 仓库根）
docker build -f deploy/elixir/im/Dockerfile -t im:local .

# 本地全栈
kubectl apply -k deploy/elixir/im/k8s/overlays/local/
./deploy/elixir/im/scripts/release-deploy-local.sh
```

---

## mise 任务约定

根目录 **无** `mix.exs`。Mix 任务在 `apps/elixir/im` 下执行（见根 `mise.toml` 的 `im:*` 别名）。

| 任务 | 说明 |
|------|------|
| `mise run proto-check` | 仓库根 proto |
| `mise run im:compile` / `im:test` | `apps/elixir/im` |
| `mise run ci` | proto + IM 项目（loadtest 在 Phase 10 加入） |

---

## CI 路径过滤

| 变更路径 | Job |
|----------|-----|
| `proto/**` | 始终 proto-check |
| `apps/elixir/im/**` | Elixir compile + test |
| `apps/elixir/loadtest/**` | loadtest（Phase 10 起） |
| `apps/web/im-console/**` | web console build（Phase 12 起） |
| `apps/java/im/**` | Java 构建（预留） |

---

## 与文档的对应

| 文档 | 范围 |
|------|------|
| [monorepo-layout.md](monorepo-layout.md) | 本文件：仓布局 |
| [elixir/project-structure.md](elixir/project-structure.md) | `apps/elixir/im/lib/` 模块树 |
| [elixir/roadmap.md](elixir/roadmap.md) | Elixir IM 实施阶段 |
| [elixir/test-client.md](elixir/test-client.md) | 自动化客户端 → `im_client` + `loadtest` |
| [web/web-console.md](web/web-console.md) | 浏览器演示 → `apps/web/im-console` |
| [java/README.md](java/README.md) | Java 预留 |

---

## 落地顺序

1. **P0-01**：`apps/elixir/im` 下 `mix new im --sup`
2. **P0-05**：在 `apps/elixir/im/lib/` 建骨架（见 project-structure）
3. **P0-03/08–10**：`deploy/elixir/im/`（已就位）
4. **Phase 2+**：可选 `apps/elixir/im_client`
5. **Phase 3+**：`apps/web/im-console`（与 IM P2–P3 对齐 MVP，见 [web-console.md](../design/web-console.md)）
6. **Phase 10**：`apps/elixir/loadtest` + `deploy/elixir/loadtest/`
