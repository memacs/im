# Changelog

本文件记录面向第三方的 **版本级变更**。协议细节以 `proto/` 与 [protocol.md](docs/design/protocol/protocol.md) 为准。

格式基于 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.0.0/)。

---

## [Unreleased]

---

## [0.1.0]

### Added

- Elixir IM 服务端 Phase 0–13：鉴权、单聊/群聊/聊天室、离线拉取、消息扩展、社交管理、集群与 Kafka 旁路
- 双通道 API：WebSocket（Protobuf）+ REST（`/api/v1`）
- 子项目：`im_client`、`loadtest`、`im-console`
- K8s 部署：`local` / `cluster` / `kafka-event-bus` overlay
- 文档体系：`module-map`、`specs-index`、HTTP API 参考、交付手册与已知限制清单
- CI：proto 校验、Elixir 测试、Release 镜像构建

### Known limitations

- 见 [docs/KNOWN-LIMITATIONS.md](docs/KNOWN-LIMITATIONS.md)

[Unreleased]: https://github.com/example/im/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/example/im/releases/tag/v0.1.0
