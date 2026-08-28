# Requirements: Phase 11 App Channel

| 项 | 内容 |
| --- | --- |
| Spec | `phase-11-app-channel` |
| Roadmap | P11-01 ~ P11-05 |
| 权威 | `proto/channel.proto`、`docs/design/app-channel.md`、protocol §27 |
| 状态 | 实施中 |

---

## Introduction

应用通道：后端 internal 下行广播 + 客户端上行上报 Kafka；尽力而为、无离线；PubSub 扇出（非树状）。

---

## User Stories

### US-1：协议与订阅

1. WHEN proto 含 CMD 900–906 与 ErrorCode 6001–6003，THE SYSTEM SHALL 已生成 `Pb.Im.Protocol.Channel*`。
2. WHEN 已鉴权客户端 `CMD_CHANNEL_SUBSCRIBE_REQ`，THE SYSTEM SHALL ACL 校验后 PubSub.subscribe，并回 `SUBSCRIBE_RESP`。
3. WHEN 断线，THE SYSTEM SHALL 自动取消本连接全部 Channel 订阅。

### US-2：限速与上行

1. WHEN 客户端 `CMD_CHANNEL_PUBLISH` 且未超限，THE SYSTEM SHALL 回 `PUBLISH_ACK` 并异步写 `im.app_events`（`APP_EVENT_UP`）。
2. WHEN 同连接超过 1/s（burst 2），THE SYSTEM SHALL **静默丢弃**（不回 ACK）。

### US-3：下行广播

1. WHEN `POST /internal/v1/channels/:ns/:name/publish` 且带 `X-IM-Caller-Service`，THE SYSTEM SHALL 预编码一次并 `PubSub.broadcast` `CMD_CHANNEL_PUSH`（seq=0）。
2. WHEN 订阅者在线，THE SYSTEM SHALL 收到 PUSH；离线不补发。
