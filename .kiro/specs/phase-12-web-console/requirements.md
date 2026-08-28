# Requirements: Phase 12 Web Console

| 项 | 内容 |
| --- | --- |
| Spec | `phase-12-web-console` |
| Roadmap | P12-01 ~ P12-16 |
| 权威 | `docs/design/web-console.md` DD-037、`proto/` |
| 状态 | 实施中 |

## Introduction

独立 SPA `apps/web/im-console`：人工演示 protocol 全部客户端能力；不打进 IM Release；不调用 `/internal/v1`。

## Acceptance

1. `npm ci && npm run build` 通过。
2. Packet Codec round-trip（Vitest）与服务端语义一致（ver=1）。
3. 登录 → WS AUTH → 发消息/收 PUSH；Coverage 页覆盖设计 §3.2。
4. 群/室/好友/Channel/扩展消息均有可操作 UI；REST 与 WS 并列入口。
5. `mise run web:dev` / `web:build` 可用。
