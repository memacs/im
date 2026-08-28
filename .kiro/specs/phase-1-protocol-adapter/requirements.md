# Requirements: Phase 1 协议适配层

| 项 | 内容 |
| --- | --- |
| Spec | `phase-1-protocol-adapter` |
| Roadmap | Phase 1（P1-01 ~ P1-05） |
| 权威协议 | `proto/` + `docs/design/protocol/protocol.md` §3–4 |
| 状态 | 已确认，可实施 |

---

## Introduction

在不依赖 WebSocket 的前提下，提供 `Packet` 二进制编解码、成功/失败响应构造、服务端推送信封构造，以及按 `CmdType` 选择 Command 模块的协议路由。业务规则不在本 Phase。

---

## User Stories

### US-1：编解码与版本门禁

**作为** 接入层，**我想** 将 WS 二进制帧与 `Packet` 互转并校验协议版本，**以便** 拒绝不兼容客户端并保证 payload 字节可交给业务层。

#### Acceptance Criteria

1. WHEN 收到 `ver = 1` 且可解析的合法 `Packet` 二进制帧，THE SYSTEM SHALL 解码为 `Pb.Im.Protocol.Packet` 结构，且再编码后关键字段与原文一致（round-trip）。
2. WHEN 收到 `ver ≠ 1`（含 `0` / 未指定）的帧，THE SYSTEM SHALL 返回错误，错误码映射为 `CODE_PROTO_VERSION_UNSUPPORTED`（1003）。
3. WHEN 收到无法按 Protobuf 解析为 `Packet` 的损坏字节，THE SYSTEM SHALL 返回错误（`CODE_MSG_INVALID`），且进程不崩溃。
4. WHEN `Packet.compression` 为 `UNSPECIFIED` 或 `NONE`，THE SYSTEM SHALL 不对 `payload` 做解压，原样保留字节（v1 仅协商 NONE）。
5. THE SYSTEM SHALL 在协议层 **不** 访问 DB / Redis / 业务 Service。

### US-2：成功响应与统一错误响应

**作为** Command 处理器，**我想** 从请求 `Packet` 构造成功响应或 `CMD_ERROR`，**以便** 客户端用 `seq` 匹配请求，并用 `ErrorBody` 定位失败命令。

#### Acceptance Criteria

1. WHEN 构造成功响应，THE SYSTEM SHALL 回传请求的 `seq`、`trace_id`、`cid`，设置 `ver = 1`，并使用调用方指定的响应 `cmd` 与 payload。
2. WHEN 构造失败响应，THE SYSTEM SHALL 使用 `cmd = CMD_ERROR`，`payload = ErrorBody`，并回传请求的 `seq` / `trace_id`。
3. WHEN `ErrorBody` 被构造，THE SYSTEM SHALL 填充 `code`（proto `ErrorCode`）、`msg`、`ref_cmd`、`ref_cid`（`ref_cid` 优先取 Error 上的值，否则回退请求 `cid`）。
4. WHEN 业务错误仅有原子 `code`（如 `:unauthorized`），THE SYSTEM SHALL 映射到 `proto/common.proto` 中对应的 `ErrorCode` 枚举值。

### US-3：服务端推送信封

**作为** 投递层，**我想** 构造 `CMD_MSG_PUSH` / `CMD_MSG_PUSH_BATCH` 等推送包，**以便** 下行无需客户端 `seq` 匹配。

#### Acceptance Criteria

1. WHEN 构造推送包，THE SYSTEM SHALL 设置 `seq = 0`、`ver = 1`。
2. WHEN 调用方提供 `trace_id` / `route_key` / `cid`，THE SYSTEM SHALL 写入对应信封字段。
3. WHEN 未提供 `ts`，THE SYSTEM SHALL 填入服务端当前毫秒时间戳。

### US-4：按 CmdType 路由（无业务）

**作为** WebSocket 接入层，**我想** 按 `cmd` 数值解析到 Command 模块，**以便** 后续 Phase 挂接具体 Handler。

#### Acceptance Criteria

1. WHEN `cmd` 已在协议路由表注册，THE SYSTEM SHALL 返回对应 `IM.WebSocket.Commands.*` 模块。
2. WHEN `cmd` 未注册或未知，THE SYSTEM SHALL 返回错误（不 raise），并带上 `ref_cmd`。
3. WHEN 查询 `CmdType` 原子 ↔ 数值，THE SYSTEM SHALL 对未知数值返回错误而非崩溃。
4. THE SYSTEM SHALL **不** 在 Router 内执行业务校验、落库或扇出。

### US-5：错误码与鉴权相关 proto 字段对齐

**作为** 实现与文档维护者，**我想** 原子错误码与 `ErrorCode` 枚举、以及 `AuthResp` / `KickNotify` 关键字段与 proto 一致，**以便** Phase 2 鉴直接使用。

#### Acceptance Criteria

1. WHEN 映射已定义的原子错误码，THE SYSTEM SHALL 得到与 `proto/common.proto` 数值一致的 `ErrorCode`。
2. WHEN 映射未知原子，THE SYSTEM SHALL 回退为 `CODE_INTERNAL_ERROR`（9000）。
3. THE SYSTEM SHALL 以测试锁定 `AuthResp.clear_local_data`、`AuthResp.payload_compression`、`KickNotify.reason_code` / `KickReason` 等已确认字段可用（生成物级，不为业务实现鉴权）。

---

## Non-Goals（本 Phase 不做）

- WebSocket Endpoint、连接状态机、鉴权成功/失败关连接（Phase 2）
- GZIP/LZ4 实际压缩/解压算法（字段解析即可）
- 具体 `Commands.*` 业务 Handler（可空路由表）
- REST / Dispatch 业务编排
