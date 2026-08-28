# Web 演示控制台 - 前端实现

| 项 | 内容 |
|------|------|
| 语言 | TypeScript（React + Vite） |
| 设计文档 | [web-console.md](../../design/web-console.md)（**权威**） |
| Roadmap | Phase 12（P12-xx）；**完成定义 = 协议能力全覆盖** |
| 协议 | 行为以 [`proto/`](../../../proto/) + [`protocol.md`](../../design/protocol/protocol.md) 为准；**禁止**擅自改协议，变更须人工确认（[`AGENTS.md`](../../../AGENTS.md)） |

> **文档分级**：独立前端 impl。行为规范见设计文档 §3 能力矩阵；本文列目录、工具链与验收要点。

---

## 1. 目录

```text
apps/web/im-console/
├── package.json
├── vite.config.ts
├── tsconfig.json
├── index.html
├── src/
│   ├── main.tsx
│   ├── api/              # REST：sessions、messages、groups、rooms、friends、channels…
│   ├── protocol/         # proto 生成的 TS + Packet 编解码
│   ├── ws/               # ImSocket：连接、AUTH、心跳、cmd 分发
│   ├── stores/           # 连接、会话、消息、各域状态
│   ├── pages/
│   │   ├── Login.tsx
│   │   ├── Chat.tsx          # 单聊/群/室消息
│   │   ├── Groups.tsx
│   │   ├── Rooms.tsx
│   │   ├── Friends.tsx
│   │   ├── Channel.tsx       # App Channel
│   │   ├── Coverage.tsx      # 协议覆盖清单（验收用）
│   │   └── Debug.tsx         # 原始 Packet、trace_id
│   └── components/
└── public/
```

**禁止**将 Console 源码放入 `apps/elixir/im/lib/im_web`（保持 Release 边界清晰）。

---

## 2. 工具链

| 工具 | 用途 |
|------|------|
| **Vite** | 开发与生产构建 |
| **TypeScript** | 类型安全 |
| **React** | UI（设计默认；换框架须更新设计文档 §2.1） |
| **protobuf-ts** 或 **@bufbuild/protobuf** | 从 `proto/` 生成 TS；与 `mise run proto-check` 同源 |
| **fetch** | REST；统一带 `Authorization`、`X-Trace-Id` |

### 本地开发

```text
# 设计目标（P12-02 落地后）
mise run web:dev          # Vite → proxy IM :4000
mise run web:build        # 产出 dist/ 静态资源
```

`vite.config.ts` 示例代理：

```ts
server: {
  proxy: {
    "/api": "http://localhost:4000",
    "/socket": { target: "ws://localhost:4000", ws: true },
  },
},
```

实际 WS 路径以 `im` Endpoint 为准（实现时与 `connection.websocket_urls` 对齐）。

---

## 3. 模块职责

| 模块 | 职责 |
|------|------|
| `api/*.ts` | 各域 REST 封装；与 WS 操作语义一致 |
| `ws/im_socket.ts` | 二进制帧、全 `CmdType` 分发、心跳、重连 |
| `protocol/codec.ts` | `Packet` encode/decode；`ver` 校验 |
| `stores/session.ts` | 当前用户、`device_id`（localStorage UUID） |
| `stores/chat.ts` | 会话、消息、`inbox_seq`、ACK/已读状态 |
| `pages/Coverage.tsx` | 设计文档 §3.2 矩阵的状态追踪 |
| `pages/Debug.tsx` | 最近包、错误码、手动触发 OFFLINE_PULL 等 |

### WS 与 REST 双入口

对 [`dual-channel-api.md`](../../design/dual-channel-api.md) 中列出的能力，相关页面须提供：

- **默认 WS**（实时演示主路径）
- **REST 并列按钮/Tab**（验证同一 `Dispatch` 结果）

仅 WS 的能力（心跳、下行 PUSH 等）在 Coverage 页标注「仅 WS」。

---

## 4. 与 IM 服务端协作

实现顺序见设计文档 §3.4；**范围不缩减**——IM 每完成一 Phase，Console 对应域须在 **同一里程碑** 将 Coverage 项标为「可演示」。

| IM Phase | Console 须补齐的 Coverage 域 |
|----------|------------------------------|
| P2 | 连接与基础设施 |
| P3 | 消息 SEND/PUSH/ACK、全 MsgType |
| P4 | 离线拉取、重连、多端 |
| P5 | 群聊 + `CMD_GROUP_*` |
| P6 | 聊天室 + `CMD_ROOM_*` |
| P7 | 已读、撤回、编辑、阅后即焚、透传、批量 ACK |
| P8 | `CMD_FRIEND_*` |
| P11 | `CMD_CHANNEL_*` |

Console **不调用** `/internal/v1`；**不超前**伪造未实现的 cmd 行为，但须保留 UI 入口与「待服务端」状态。

---

## 5. 测试

| 类型 | 方式 |
|------|------|
| 单元 | Vitest：`codec` round-trip、store 纯函数、Coverage 状态机 |
| E2E | Playwright（可选）：按 Coverage 清单抽样冒烟 |
| 协议回归 | **仍以** `im_client` + ExUnit 为主；Console 用于人工全协议走查 |

遵循 [`AGENTS.md`](../../../AGENTS.md)：**禁止 sleep 同步**；E2E 用 `waitFor` / 网络空闲，不用 `page.waitForTimeout` 赌时序（真实退避测试除外并注释）。

---

## 6. 验收要点（Phase 12 完成）

- [x] `apps/web/im-console` 可 `npm ci && npm run build`
- [x] **Coverage 页**：设计文档 §3.2 每一项均有状态；已实现 IM 能力均为「可演示」
- [x] 双用户多 Tab：单聊/群/室收发、ACK、已读、撤回、编辑、阅后即焚、透传可人工走通
- [x] 群/室/好友/Channel 管理 cmd 均有可操作 UI（随 IM Phase 逐步变绿）
- [x] 支持全部 `MsgType` 的发送表单（至少 mock 附件 URL 或占位 content）
- [x] 双通道：发消息、离线拉取、好友/群/室操作等至少各 **1 项** REST 与 WS 对照成功
- [x] 断线重连 + `OFFLINE_PULL` 不丢消息（IM P4 就绪后）
- [x] 不调用 `/internal/v1`；静态资源不包含密钥

---

## 7. 相关链接

| 文档 | 说明 |
| --- | --- |
| [docs/README.md](../../README.md) | 文档总索引 |
| [module-map.md](../../module-map.md) | 功能对照表 |
| [web-console 设计](../../design/web-console.md) | 能力矩阵（权威） |
| [apps/web/im-console/README.md](../../../apps/web/im-console/README.md) | 启动、配置、部署 |
| [specs-index.md](../../specs-index.md) | [phase-12-web-console](../../../.kiro/specs/phase-12-web-console/) |
| [release-deploy-test.md](../elixir/release-deploy-test.md) | IM 集群冒烟后再验 Console |
| [test-client.md](../elixir/test-client.md) | 自动化客户端（非 UI） |
| [dual-channel-api.md](../../design/dual-channel-api.md) | REST 路径对照 |
| [http-api-reference.md](../elixir/http-api-reference.md) | REST 逐接口文档 |
