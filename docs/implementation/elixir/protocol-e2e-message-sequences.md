# 协议 E2E 消息时序与字段详解（im_client）

| 项 | 内容 |
| --- | --- |
| 测试目录 | `apps/elixir/im/test/im_client/protocol/` |
| **实测报文 JSON** | [`protocol-e2e-traces.json`](protocol-e2e-traces.json)（`TRACE_EXPORT=1 mix test.trace` 自动生成） |
| 重新生成 | `PGPORT=15432 TRACE_EXPORT=1 CLUSTER_E2E=1 mix test.trace` |
| 协议权威 | [`proto/`](../../../proto/) + [`protocol.md`](../../design/protocol/protocol.md) |

本文每个用例的 **字段值均来自 E2E trace 导出**（与 `test/im_client/protocol/*_test.exs` 同步）。
`msg_id`/`session_id`/`access_token` 等每次运行会变，但 **字段结构与相对关系** 与线上一致。

> **维护约定**：新增或修改 protocol E2E 用例时，须添加 `@tag trace_case` 并在关键步骤调用 `trace!/2`；
> 提交前运行 `mix test.trace` 更新本文与 JSON。`trace_coverage_test.exs` 会校验用例清单完整。

---

## 1. Packet 信封字段（所有 WS 帧共有）

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `ver` | uint32 | 协议版本，当前 = 1 |
| `cmd` | uint32 | 命令字，见 CmdType |
| `seq` | uint64 | 客户端请求序号；**推送包 = 0** |
| `ts` | int64 | 发送时间戳（ms） |
| `cid` | string | 请求级幂等；与 `client_msg_id` 职责分离 |
| `trace_id` | string | 链路追踪 ID |
| `route_key` | string | 网关/集群分流键 |
| `compression` | enum | payload 压缩；鉴权后多为 NONE |
| `payload` | bytes | Protobuf 业务体 |

---

## 用例索引（E2E 实测 trace）

1. [auth_guard_test/token 与 device_id 不匹配](#auth_guard_test/token%20%E4%B8%8E%20device_id%20%E4%B8%8D%E5%8C%B9%E9%85%8D)
2. [auth_guard_test/token 与 user_id 不匹配](#auth_guard_test/token%20%E4%B8%8E%20user_id%20%E4%B8%8D%E5%8C%B9%E9%85%8D)
3. [auth_guard_test/封禁设备 AUTH](#auth_guard_test/%E5%B0%81%E7%A6%81%E8%AE%BE%E5%A4%87%20AUTH)
4. [auth_guard_test/已吊销 token](#auth_guard_test/%E5%B7%B2%E5%90%8A%E9%94%80%20token)
5. [auth_guard_test/已鉴权再发 AUTH](#auth_guard_test/%E5%B7%B2%E9%89%B4%E6%9D%83%E5%86%8D%E5%8F%91%20AUTH)
6. [auth_guard_test/无效 token](#auth_guard_test/%E6%97%A0%E6%95%88%20token)
7. [auth_guard_test/未鉴权发 MSG_SEND 静默关闭](#auth_guard_test/%E6%9C%AA%E9%89%B4%E6%9D%83%E5%8F%91%20MSG_SEND%20%E9%9D%99%E9%BB%98%E5%85%B3%E9%97%AD)
8. [auth_guard_test/未鉴权发心跳静默关闭](#auth_guard_test/%E6%9C%AA%E9%89%B4%E6%9D%83%E5%8F%91%E5%BF%83%E8%B7%B3%E9%9D%99%E9%BB%98%E5%85%B3%E9%97%AD)
9. [auth_guard_test/过期 token](#auth_guard_test/%E8%BF%87%E6%9C%9F%20token)
10. [auth_guard_test/连接中 token 过期 CMD_KICK](#auth_guard_test/%E8%BF%9E%E6%8E%A5%E4%B8%AD%20token%20%E8%BF%87%E6%9C%9F%20CMD_KICK)
11. [auth_guard_test/鉴权超时静默关闭](#auth_guard_test/%E9%89%B4%E6%9D%83%E8%B6%85%E6%97%B6%E9%9D%99%E9%BB%98%E5%85%B3%E9%97%AD)
12. [channel_test/订阅与 publish](#channel_test/%E8%AE%A2%E9%98%85%E4%B8%8E%20publish)
13. [cluster_test/跨节点 PUSH 单聊](#cluster_test/%E8%B7%A8%E8%8A%82%E7%82%B9%20PUSH%20%E5%8D%95%E8%81%8A)
14. [cluster_test/跨节点 erpc 转发](#cluster_test/%E8%B7%A8%E8%8A%82%E7%82%B9%20erpc%20%E8%BD%AC%E5%8F%91)
15. [connection_test/GET metrics](#connection_test/GET%20metrics)
16. [connection_test/REST 登录 + WS AUTH + 心跳](#connection_test/REST%20%E7%99%BB%E5%BD%95%20+%20WS%20AUTH%20+%20%E5%BF%83%E8%B7%B3)
17. [connection_test/登出 DELETE sessions](#connection_test/%E7%99%BB%E5%87%BA%20DELETE%20sessions)
18. [conversation_test/REST 会话列表未读与已读同步](#conversation_test/REST%20%E4%BC%9A%E8%AF%9D%E5%88%97%E8%A1%A8%E6%9C%AA%E8%AF%BB%E4%B8%8E%E5%B7%B2%E8%AF%BB%E5%90%8C%E6%AD%A5)
19. [conversation_test/群聊会话列表未读](#conversation_test/%E7%BE%A4%E8%81%8A%E4%BC%9A%E8%AF%9D%E5%88%97%E8%A1%A8%E6%9C%AA%E8%AF%BB)
20. [extensions_test/已读回执](#extensions_test/%E5%B7%B2%E8%AF%BB%E5%9B%9E%E6%89%A7)
21. [extensions_test/撤回消息](#extensions_test/%E6%92%A4%E5%9B%9E%E6%B6%88%E6%81%AF)
22. [extensions_test/编辑消息](#extensions_test/%E7%BC%96%E8%BE%91%E6%B6%88%E6%81%AF)
23. [extensions_test/透传指令](#extensions_test/%E9%80%8F%E4%BC%A0%E6%8C%87%E4%BB%A4)
24. [extensions_test/阅后即焚：已读后双方收到 BURN_PUSH](#extensions_test/%E9%98%85%E5%90%8E%E5%8D%B3%E7%84%9A%EF%BC%9A%E5%B7%B2%E8%AF%BB%E5%90%8E%E5%8F%8C%E6%96%B9%E6%94%B6%E5%88%B0%20BURN_PUSH)
25. [friend_policy_test/require_friend_to_send](#friend_policy_test/require_friend_to_send)
26. [friend_test/好友请求列表](#friend_test/%E5%A5%BD%E5%8F%8B%E8%AF%B7%E6%B1%82%E5%88%97%E8%A1%A8)
27. [friend_test/拉黑与取消拉黑](#friend_test/%E6%8B%89%E9%BB%91%E4%B8%8E%E5%8F%96%E6%B6%88%E6%8B%89%E9%BB%91)
28. [friend_test/拒绝好友请求](#friend_test/%E6%8B%92%E7%BB%9D%E5%A5%BD%E5%8F%8B%E8%AF%B7%E6%B1%82)
29. [friend_test/添加-接受-列表-备注-删除](#friend_test/%E6%B7%BB%E5%8A%A0-%E6%8E%A5%E5%8F%97-%E5%88%97%E8%A1%A8-%E5%A4%87%E6%B3%A8-%E5%88%A0%E9%99%A4)
30. [group_test/群生命周期与群消息](#group_test/%E7%BE%A4%E7%94%9F%E5%91%BD%E5%91%A8%E6%9C%9F%E4%B8%8E%E7%BE%A4%E6%B6%88%E6%81%AF)
31. [offline_test/离线消息可通过 CMD_OFFLINE_PULL 拉取](#offline_test/%E7%A6%BB%E7%BA%BF%E6%B6%88%E6%81%AF%E5%8F%AF%E9%80%9A%E8%BF%87%20CMD_OFFLINE_PULL%20%E6%8B%89%E5%8F%96)
32. [private_message_test/A 发单聊 → B 收 PUSH + 客户端 ACK](#private_message_test/A%20%E5%8F%91%E5%8D%95%E8%81%8A%20%E2%86%92%20B%20%E6%94%B6%20PUSH%20+%20%E5%AE%A2%E6%88%B7%E7%AB%AF%20ACK)
33. [private_message_test/REST 发消息双通道](#private_message_test/REST%20%E5%8F%91%E6%B6%88%E6%81%AF%E5%8F%8C%E9%80%9A%E9%81%93)
34. [private_message_test/client_msg_id 幂等](#private_message_test/client_msg_id%20%E5%B9%82%E7%AD%89)
35. [private_message_test/批量 ACK](#private_message_test/%E6%89%B9%E9%87%8F%20ACK)
36. [room_test/聊天室生命周期与广播](#room_test/%E8%81%8A%E5%A4%A9%E5%AE%A4%E7%94%9F%E5%91%BD%E5%91%A8%E6%9C%9F%E4%B8%8E%E5%B9%BF%E6%92%AD)
37. [session_test/内部 kick 在线设备收到 CMD_KICK](#session_test/%E5%86%85%E9%83%A8%20kick%20%E5%9C%A8%E7%BA%BF%E8%AE%BE%E5%A4%87%E6%94%B6%E5%88%B0%20CMD_KICK)
38. [session_test/同平台超限 kick_oldest 踢掉旧设备](#session_test/%E5%90%8C%E5%B9%B3%E5%8F%B0%E8%B6%85%E9%99%90%20kick_oldest%20%E8%B8%A2%E6%8E%89%E6%97%A7%E8%AE%BE%E5%A4%87)
39. [session_test/同平台超限 reject 鉴权失败](#session_test/%E5%90%8C%E5%B9%B3%E5%8F%B0%E8%B6%85%E9%99%90%20reject%20%E9%89%B4%E6%9D%83%E5%A4%B1%E8%B4%A5)
40. [stream_test/MSG_STREAM 四段推送至对端](#stream_test/MSG_STREAM%20%E5%9B%9B%E6%AE%B5%E6%8E%A8%E9%80%81%E8%87%B3%E5%AF%B9%E7%AB%AF)
41. [stream_test/MSG_STREAM 离线拉取](#stream_test/MSG_STREAM%20%E7%A6%BB%E7%BA%BF%E6%8B%89%E5%8F%96)
42. [stream_test/流式透传 stream_start/chunk/end](#stream_test/%E6%B5%81%E5%BC%8F%E9%80%8F%E4%BC%A0%20stream_start/chunk/end)

---

## auth_guard_test/token 与 device_id 不匹配
### 步骤 2：↑ WS CMD_AUTH_REQ（client）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `1` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_AUTH_REQ` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `1` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886841` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `app_key` | `app_demo` | 租户应用标识 |
| `compression_offered` | `[]` |  |
| `device_id` | `wrong-device-2408` | 设备唯一标识 |
| `device_model` | `` |  |
| `device_name` | `` |  |
| `network` | `` |  |
| `os` | `` |  |
| `platform` | `ios` | 客户端平台：ios/android/web/desktop |
| `sdk_ver` | `0.1.0` | SDK 版本号 |
| `token` | `flyecjuRhk_Ee1VT3pNhmk8RrLYAuznkDbN25Hg8t2w` | WS 鉴权 token（与 REST access_token 相同） |
| `user_id` | `user_8167` | 业务用户 ID |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "client",
  "case": "auth_guard_test/token 与 device_id 不匹配",
  "direction": "↑ WS CMD_AUTH_REQ",
  "note": "↑ WS CMD_AUTH_REQ",
  "packet": {
    "cid": "",
    "cmd": 1,
    "cmd_name": "CMD_AUTH_REQ",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "app_key": "app_demo",
      "compression_offered": [],
      "device_id": "wrong-device-2408",
      "device_model": "",
      "device_name": "",
      "network": "",
      "os": "",
      "platform": "ios",
      "sdk_ver": "0.1.0",
      "token": "flyecjuRhk_Ee1VT3pNhmk8RrLYAuznkDbN25Hg8t2w",
      "user_id": "user_8167"
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785909886841,
    "ver": 1
  },
  "step": 2
}
```

</details>

### 步骤 3：↓ WS CMD_ERROR（client）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `6` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_ERROR` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `1` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886844` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `code` | `CODE_UNAUTHORIZED` | ErrorCode 枚举值 |
| `msg` | `device_id mismatch` | 人类可读错误说明 |
| `ref_cid` | `` |  |
| `ref_cmd` | `1` | 引发错误的原始请求 cmd |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "client",
  "case": "auth_guard_test/token 与 device_id 不匹配",
  "direction": "↓ WS CMD_ERROR",
  "note": "↓ WS CMD_ERROR",
  "packet": {
    "cid": "",
    "cmd": 6,
    "cmd_name": "CMD_ERROR",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "code": "CODE_UNAUTHORIZED",
      "msg": "device_id mismatch",
      "ref_cid": "",
      "ref_cmd": 1
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785909886844,
    "ver": 1
  },
  "step": 3
}
```

</details>

---

## auth_guard_test/token 与 user_id 不匹配
### 步骤 2：↑ WS CMD_AUTH_REQ（client）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `1` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_AUTH_REQ` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `1` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886849` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `app_key` | `app_demo` | 租户应用标识 |
| `compression_offered` | `[]` |  |
| `device_id` | `device_2472` | 设备唯一标识 |
| `device_model` | `` |  |
| `device_name` | `` |  |
| `network` | `` |  |
| `os` | `` |  |
| `platform` | `ios` | 客户端平台：ios/android/web/desktop |
| `sdk_ver` | `0.1.0` | SDK 版本号 |
| `token` | `dmJQ3JQddQ2PG-uOTQpuyYo6X13gmP1xHPnhYfbLS1U` | WS 鉴权 token（与 REST access_token 相同） |
| `user_id` | `wrong-user-2504` | 业务用户 ID |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "client",
  "case": "auth_guard_test/token 与 user_id 不匹配",
  "direction": "↑ WS CMD_AUTH_REQ",
  "note": "↑ WS CMD_AUTH_REQ",
  "packet": {
    "cid": "",
    "cmd": 1,
    "cmd_name": "CMD_AUTH_REQ",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "app_key": "app_demo",
      "compression_offered": [],
      "device_id": "device_2472",
      "device_model": "",
      "device_name": "",
      "network": "",
      "os": "",
      "platform": "ios",
      "sdk_ver": "0.1.0",
      "token": "dmJQ3JQddQ2PG-uOTQpuyYo6X13gmP1xHPnhYfbLS1U",
      "user_id": "wrong-user-2504"
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785909886849,
    "ver": 1
  },
  "step": 2
}
```

</details>

### 步骤 3：↓ WS CMD_ERROR（client）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `6` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_ERROR` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `1` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886851` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `code` | `CODE_UNAUTHORIZED` | ErrorCode 枚举值 |
| `msg` | `user_id mismatch` | 人类可读错误说明 |
| `ref_cid` | `` |  |
| `ref_cmd` | `1` | 引发错误的原始请求 cmd |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "client",
  "case": "auth_guard_test/token 与 user_id 不匹配",
  "direction": "↓ WS CMD_ERROR",
  "note": "↓ WS CMD_ERROR",
  "packet": {
    "cid": "",
    "cmd": 6,
    "cmd_name": "CMD_ERROR",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "code": "CODE_UNAUTHORIZED",
      "msg": "user_id mismatch",
      "ref_cid": "",
      "ref_cmd": 1
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785909886851,
    "ver": 1
  },
  "step": 3
}
```

</details>

---

## auth_guard_test/封禁设备 AUTH
### 步骤 2：↑ WS CMD_AUTH_REQ（client）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `1` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_AUTH_REQ` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `1` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909887805` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `app_key` | `app_demo` | 租户应用标识 |
| `compression_offered` | `[]` |  |
| `device_id` | `device_8647` | 设备唯一标识 |
| `device_model` | `` |  |
| `device_name` | `` |  |
| `network` | `` |  |
| `os` | `` |  |
| `platform` | `ios` | 客户端平台：ios/android/web/desktop |
| `sdk_ver` | `0.1.0` | SDK 版本号 |
| `token` | `n7kUX9mw42CJavXG_YDePWUAS_Pp3YIFb_Co04Sba3I` | WS 鉴权 token（与 REST access_token 相同） |
| `user_id` | `user_395` | 业务用户 ID |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "client",
  "case": "auth_guard_test/封禁设备 AUTH",
  "direction": "↑ WS CMD_AUTH_REQ",
  "note": "↑ WS CMD_AUTH_REQ",
  "packet": {
    "cid": "",
    "cmd": 1,
    "cmd_name": "CMD_AUTH_REQ",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "app_key": "app_demo",
      "compression_offered": [],
      "device_id": "device_8647",
      "device_model": "",
      "device_name": "",
      "network": "",
      "os": "",
      "platform": "ios",
      "sdk_ver": "0.1.0",
      "token": "n7kUX9mw42CJavXG_YDePWUAS_Pp3YIFb_Co04Sba3I",
      "user_id": "user_395"
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785909887805,
    "ver": 1
  },
  "step": 2
}
```

</details>

### 步骤 3：↓ WS CMD_ERROR（client）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `6` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_ERROR` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `1` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909887812` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `code` | `CODE_UNAUTHORIZED` | ErrorCode 枚举值 |
| `msg` | `device_banned` | 人类可读错误说明 |
| `ref_cid` | `` |  |
| `ref_cmd` | `1` | 引发错误的原始请求 cmd |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "client",
  "case": "auth_guard_test/封禁设备 AUTH",
  "direction": "↓ WS CMD_ERROR",
  "note": "↓ WS CMD_ERROR",
  "packet": {
    "cid": "",
    "cmd": 6,
    "cmd_name": "CMD_ERROR",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "code": "CODE_UNAUTHORIZED",
      "msg": "device_banned",
      "ref_cid": "",
      "ref_cmd": 1
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785909887812,
    "ver": 1
  },
  "step": 3
}
```

</details>

---

## auth_guard_test/已吊销 token
### 步骤 2：↑ WS CMD_AUTH_REQ（client）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `1` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_AUTH_REQ` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `1` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886861` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `app_key` | `app_demo` | 租户应用标识 |
| `compression_offered` | `[]` |  |
| `device_id` | `device_8455` | 设备唯一标识 |
| `device_model` | `` |  |
| `device_name` | `` |  |
| `network` | `` |  |
| `os` | `` |  |
| `platform` | `ios` | 客户端平台：ios/android/web/desktop |
| `sdk_ver` | `0.1.0` | SDK 版本号 |
| `token` | `FG4pZ3i9BWtaXxWIaoxU2dq2rB8DftPEWdylqpBkqWs` | WS 鉴权 token（与 REST access_token 相同） |
| `user_id` | `user_8423` | 业务用户 ID |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "client",
  "case": "auth_guard_test/已吊销 token",
  "direction": "↑ WS CMD_AUTH_REQ",
  "note": "↑ WS CMD_AUTH_REQ",
  "packet": {
    "cid": "",
    "cmd": 1,
    "cmd_name": "CMD_AUTH_REQ",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "app_key": "app_demo",
      "compression_offered": [],
      "device_id": "device_8455",
      "device_model": "",
      "device_name": "",
      "network": "",
      "os": "",
      "platform": "ios",
      "sdk_ver": "0.1.0",
      "token": "FG4pZ3i9BWtaXxWIaoxU2dq2rB8DftPEWdylqpBkqWs",
      "user_id": "user_8423"
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785909886861,
    "ver": 1
  },
  "step": 2
}
```

</details>

### 步骤 3：↓ WS CMD_ERROR（client）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `6` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_ERROR` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `1` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886862` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `code` | `CODE_UNAUTHORIZED` | ErrorCode 枚举值 |
| `msg` | `token revoked` | 人类可读错误说明 |
| `ref_cid` | `` |  |
| `ref_cmd` | `1` | 引发错误的原始请求 cmd |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "client",
  "case": "auth_guard_test/已吊销 token",
  "direction": "↓ WS CMD_ERROR",
  "note": "↓ WS CMD_ERROR",
  "packet": {
    "cid": "",
    "cmd": 6,
    "cmd_name": "CMD_ERROR",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "code": "CODE_UNAUTHORIZED",
      "msg": "token revoked",
      "ref_cid": "",
      "ref_cmd": 1
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785909886862,
    "ver": 1
  },
  "step": 3
}
```

</details>

---

## auth_guard_test/已鉴权再发 AUTH
### 步骤 2：↑ WS CMD_AUTH_REQ (重复)（client）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `1` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_AUTH_REQ` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `1` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886856` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `app_key` | `app_demo` | 租户应用标识 |
| `compression_offered` | `[]` |  |
| `device_id` | `device_8295` | 设备唯一标识 |
| `device_model` | `` |  |
| `device_name` | `` |  |
| `network` | `` |  |
| `os` | `` |  |
| `platform` | `ios` | 客户端平台：ios/android/web/desktop |
| `sdk_ver` | `1.0.0` | SDK 版本号 |
| `token` | `BD7Mv3q2PZeajnmiB6Q7VqVAqHui2qp1PqsWwbUSLp4` | WS 鉴权 token（与 REST access_token 相同） |
| `user_id` | `user_420` | 业务用户 ID |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "client",
  "case": "auth_guard_test/已鉴权再发 AUTH",
  "direction": "↑ WS CMD_AUTH_REQ (重复)",
  "note": "↑ WS CMD_AUTH_REQ (重复)",
  "packet": {
    "cid": "",
    "cmd": 1,
    "cmd_name": "CMD_AUTH_REQ",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "app_key": "app_demo",
      "compression_offered": [],
      "device_id": "device_8295",
      "device_model": "",
      "device_name": "",
      "network": "",
      "os": "",
      "platform": "ios",
      "sdk_ver": "1.0.0",
      "token": "BD7Mv3q2PZeajnmiB6Q7VqVAqHui2qp1PqsWwbUSLp4",
      "user_id": "user_420"
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785909886856,
    "ver": 1
  },
  "step": 2
}
```

</details>

### 步骤 3：↓ WS CMD_ERROR（client）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `6` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_ERROR` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `2` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886856` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `code` | `CODE_UNAUTHORIZED` | ErrorCode 枚举值 |
| `msg` | `already_authenticated` | 人类可读错误说明 |
| `ref_cid` | `` |  |
| `ref_cmd` | `1` | 引发错误的原始请求 cmd |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "client",
  "case": "auth_guard_test/已鉴权再发 AUTH",
  "direction": "↓ WS CMD_ERROR",
  "note": "↓ WS CMD_ERROR",
  "packet": {
    "cid": "",
    "cmd": 6,
    "cmd_name": "CMD_ERROR",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "code": "CODE_UNAUTHORIZED",
      "msg": "already_authenticated",
      "ref_cid": "",
      "ref_cmd": 1
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785909886856,
    "ver": 1
  },
  "step": 3
}
```

</details>

---

## auth_guard_test/无效 token
### 步骤 2：↑ WS CMD_AUTH_REQ（client）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `1` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_AUTH_REQ` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `1` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886845` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `app_key` | `app_demo` | 租户应用标识 |
| `compression_offered` | `[]` |  |
| `device_id` | `d-331` | 设备唯一标识 |
| `device_model` | `` |  |
| `device_name` | `` |  |
| `network` | `` |  |
| `os` | `` |  |
| `platform` | `ios` | 客户端平台：ios/android/web/desktop |
| `sdk_ver` | `0.1.0` | SDK 版本号 |
| `token` | `not-a-valid-token` | WS 鉴权 token（与 REST access_token 相同） |
| `user_id` | `user_299` | 业务用户 ID |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "client",
  "case": "auth_guard_test/无效 token",
  "direction": "↑ WS CMD_AUTH_REQ",
  "note": "↑ WS CMD_AUTH_REQ",
  "packet": {
    "cid": "",
    "cmd": 1,
    "cmd_name": "CMD_AUTH_REQ",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "app_key": "app_demo",
      "compression_offered": [],
      "device_id": "d-331",
      "device_model": "",
      "device_name": "",
      "network": "",
      "os": "",
      "platform": "ios",
      "sdk_ver": "0.1.0",
      "token": "not-a-valid-token",
      "user_id": "user_299"
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785909886845,
    "ver": 1
  },
  "step": 2
}
```

</details>

### 步骤 3：↓ WS CMD_ERROR（client）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `6` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_ERROR` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `1` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886846` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `code` | `CODE_UNAUTHORIZED` | ErrorCode 枚举值 |
| `msg` | `token not found` | 人类可读错误说明 |
| `ref_cid` | `` |  |
| `ref_cmd` | `1` | 引发错误的原始请求 cmd |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "client",
  "case": "auth_guard_test/无效 token",
  "direction": "↓ WS CMD_ERROR",
  "note": "↓ WS CMD_ERROR",
  "packet": {
    "cid": "",
    "cmd": 6,
    "cmd_name": "CMD_ERROR",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "code": "CODE_UNAUTHORIZED",
      "msg": "token not found",
      "ref_cid": "",
      "ref_cmd": 1
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785909886846,
    "ver": 1
  },
  "step": 3
}
```

</details>

---

## auth_guard_test/未鉴权发 MSG_SEND 静默关闭
### 步骤 2：↑ WS CMD_MSG_SEND (未鉴权)（client）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `100` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_SEND` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `1` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909887815` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `message` | `{"burn_after_read":"false","burn_ttl_sec":0,"burned":"false","chat_type":"CHAT_PRIVATE","client_msg_id":"cm-2536","content":"illegal","conv_id":"","conv_seq":0,"edit_version":0,"ext":{},"from":"u1","inbox_seq":0,"msg_id":"","msg_type":"MSG_TEXT","priority":"MSG_PRIORITY_NORMAL","recalled":"false","server_time":0,"target_users":[],"to":"u2"}` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "client",
  "case": "auth_guard_test/未鉴权发 MSG_SEND 静默关闭",
  "direction": "↑ WS CMD_MSG_SEND (未鉴权)",
  "note": "↑ WS CMD_MSG_SEND (未鉴权)",
  "packet": {
    "cid": "",
    "cmd": 100,
    "cmd_name": "CMD_MSG_SEND",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "message": {
        "burn_after_read": "false",
        "burn_ttl_sec": 0,
        "burned": "false",
        "chat_type": "CHAT_PRIVATE",
        "client_msg_id": "cm-2536",
        "content": "illegal",
        "conv_id": "",
        "conv_seq": 0,
        "edit_version": 0,
        "ext": {},
        "from": "u1",
        "inbox_seq": 0,
        "msg_id": "",
        "msg_type": "MSG_TEXT",
        "priority": "MSG_PRIORITY_NORMAL",
        "recalled": "false",
        "server_time": 0,
        "target_users": [],
        "to": "u2"
      }
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785909887815,
    "ver": 1
  },
  "step": 2
}
```

</details>

### 步骤 3：↓ WS 连接静默关闭（client）

**事件（无 WS 报文）**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `detail` | `未鉴权发 MSG_SEND` | 事件补充说明 |
| `event` | `silent_close` | 非 WS 报文事件类型 |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "client",
  "case": "auth_guard_test/未鉴权发 MSG_SEND 静默关闭",
  "direction": "↓ WS 连接静默关闭",
  "event": {
    "detail": "未鉴权发 MSG_SEND",
    "event": "silent_close"
  },
  "note": "↓ WS 连接静默关闭",
  "step": 3
}
```

</details>

---

## auth_guard_test/未鉴权发心跳静默关闭
### 步骤 2：↑ WS CMD_HEARTBEAT_REQ (未鉴权)（client）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `3` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_HEARTBEAT_REQ` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `1` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886863` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `client_time` | `1` | 客户端本地时间（毫秒） |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "client",
  "case": "auth_guard_test/未鉴权发心跳静默关闭",
  "direction": "↑ WS CMD_HEARTBEAT_REQ (未鉴权)",
  "note": "↑ WS CMD_HEARTBEAT_REQ (未鉴权)",
  "packet": {
    "cid": "",
    "cmd": 3,
    "cmd_name": "CMD_HEARTBEAT_REQ",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "client_time": 1
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785909886863,
    "ver": 1
  },
  "step": 2
}
```

</details>

### 步骤 3：↓ WS 连接静默关闭（client）

**事件（无 WS 报文）**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `detail` | `未鉴权发心跳，无 CMD_ERROR` | 事件补充说明 |
| `event` | `silent_close` | 非 WS 报文事件类型 |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "client",
  "case": "auth_guard_test/未鉴权发心跳静默关闭",
  "direction": "↓ WS 连接静默关闭",
  "event": {
    "detail": "未鉴权发心跳，无 CMD_ERROR",
    "event": "silent_close"
  },
  "note": "↓ WS 连接静默关闭",
  "step": 3
}
```

</details>

---

## auth_guard_test/过期 token
### 步骤 2：↑ WS CMD_AUTH_REQ（client）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `1` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_AUTH_REQ` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `1` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909887786` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `app_key` | `app_demo` | 租户应用标识 |
| `compression_offered` | `[]` |  |
| `device_id` | `device_1926` | 设备唯一标识 |
| `device_model` | `` |  |
| `device_name` | `` |  |
| `network` | `` |  |
| `os` | `` |  |
| `platform` | `ios` | 客户端平台：ios/android/web/desktop |
| `sdk_ver` | `0.1.0` | SDK 版本号 |
| `token` | `nF-wQi9-3Ex9enSQD_bk7zGk-ucRQgIox-G2GWu8G5s` | WS 鉴权 token（与 REST access_token 相同） |
| `user_id` | `user_363` | 业务用户 ID |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "client",
  "case": "auth_guard_test/过期 token",
  "direction": "↑ WS CMD_AUTH_REQ",
  "note": "↑ WS CMD_AUTH_REQ",
  "packet": {
    "cid": "",
    "cmd": 1,
    "cmd_name": "CMD_AUTH_REQ",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "app_key": "app_demo",
      "compression_offered": [],
      "device_id": "device_1926",
      "device_model": "",
      "device_name": "",
      "network": "",
      "os": "",
      "platform": "ios",
      "sdk_ver": "0.1.0",
      "token": "nF-wQi9-3Ex9enSQD_bk7zGk-ucRQgIox-G2GWu8G5s",
      "user_id": "user_363"
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785909887786,
    "ver": 1
  },
  "step": 2
}
```

</details>

### 步骤 3：↓ WS CMD_ERROR（client）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `6` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_ERROR` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `1` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909887791` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `code` | `CODE_UNAUTHORIZED` | ErrorCode 枚举值 |
| `msg` | `token expired` | 人类可读错误说明 |
| `ref_cid` | `` |  |
| `ref_cmd` | `1` | 引发错误的原始请求 cmd |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "client",
  "case": "auth_guard_test/过期 token",
  "direction": "↓ WS CMD_ERROR",
  "note": "↓ WS CMD_ERROR",
  "packet": {
    "cid": "",
    "cmd": 6,
    "cmd_name": "CMD_ERROR",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "code": "CODE_UNAUTHORIZED",
      "msg": "token expired",
      "ref_cid": "",
      "ref_cmd": 1
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785909887791,
    "ver": 1
  },
  "step": 3
}
```

</details>

---

## auth_guard_test/连接中 token 过期 CMD_KICK
### 步骤 1：↓ WS CMD_KICK (token_expired)（client）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `5` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_KICK` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `0` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `a3c04e32-1f0b-4c43-b2df-52ccef0248df` | 链路追踪 ID |
| `ts` | `1785909888430` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `clear_local_data` | `false` |  |
| `kicker` | `` |  |
| `reason` | `token_expired` | 踢下线/撤回等原因 |
| `reason_code` | `KICK_REASON_TOKEN_EXPIRED` | KickReason 枚举 |
| `timestamp` | `1785909888429` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "client",
  "case": "auth_guard_test/连接中 token 过期 CMD_KICK",
  "direction": "↓ WS CMD_KICK (token_expired)",
  "note": "↓ WS CMD_KICK (token_expired)",
  "packet": {
    "cid": "",
    "cmd": 5,
    "cmd_name": "CMD_KICK",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "clear_local_data": "false",
      "kicker": null,
      "reason": "token_expired",
      "reason_code": "KICK_REASON_TOKEN_EXPIRED",
      "timestamp": 1785909888429
    },
    "route_key": "",
    "seq": 0,
    "trace_id": "a3c04e32-1f0b-4c43-b2df-52ccef0248df",
    "ts": 1785909888430,
    "ver": 1
  },
  "step": 1
}
```

</details>

---

## auth_guard_test/鉴权超时静默关闭
### 步骤 1：↓ WS 连接静默关闭（client）

**事件（无 WS 报文）**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `detail` | `AUTH 超时未发送 CMD_AUTH_REQ` | 事件补充说明 |
| `event` | `silent_close` | 非 WS 报文事件类型 |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "client",
  "case": "auth_guard_test/鉴权超时静默关闭",
  "direction": "↓ WS 连接静默关闭",
  "event": {
    "detail": "AUTH 超时未发送 CMD_AUTH_REQ",
    "event": "silent_close"
  },
  "note": "↓ WS 连接静默关闭",
  "step": 1
}
```

</details>

---

## channel_test/订阅与 publish
### 步骤 1：↓ WS CMD_CHANNEL_SUBSCRIBE_RESP（client）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `901` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_CHANNEL_SUBSCRIBE_RESP` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `2` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886830` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `failed` | `[]` |  |
| `subscribed` | `["news:alerts"]` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "client",
  "case": "channel_test/订阅与 publish",
  "direction": "↓ WS CMD_CHANNEL_SUBSCRIBE_RESP",
  "note": "↓ WS CMD_CHANNEL_SUBSCRIBE_RESP",
  "packet": {
    "cid": "",
    "cmd": 901,
    "cmd_name": "CMD_CHANNEL_SUBSCRIBE_RESP",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "failed": [],
      "subscribed": [
        "news:alerts"
      ]
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785909886830,
    "ver": 1
  },
  "step": 1
}
```

</details>

### 步骤 2：↑ HTTP POST /internal/v1/channels/.../publish（client）

**HTTP 请求体**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `channel` | `news:alerts` |  |

**HTTP 响应体（节选）**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `status` | `200` | ACK 状态：ACK_SERVER_RECEIVED / ACK_CLIENT_RECEIVED |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "client",
  "case": "channel_test/订阅与 publish",
  "direction": "↑ HTTP POST /internal/v1/channels/.../publish",
  "http": {
    "request": {
      "channel": "news:alerts"
    },
    "response": {
      "status": 200
    }
  },
  "note": "↑ HTTP POST /internal/v1/channels/.../publish",
  "step": 2
}
```

</details>

### 步骤 3：↓ WS CMD_CHANNEL_PUSH（client）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `906` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_CHANNEL_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `news:alerts` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `0` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `tr-2376` | 链路追踪 ID |
| `ts` | `1785909886832` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `caller_service` | `protocol-e2e` |  |
| `channel_id` | `news:alerts` | 应用通道 ID（namespace:name） |
| `content_type` | `application/json` |  |
| `event_id` | `46cb2fc1-d010-4499-8c84-c323c8093d72` |  |
| `payload` | `{"n":1}` |  |
| `server_time` | `1785909886831` | 服务端当前时间（毫秒） |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "client",
  "case": "channel_test/订阅与 publish",
  "direction": "↓ WS CMD_CHANNEL_PUSH",
  "note": "↓ WS CMD_CHANNEL_PUSH",
  "packet": {
    "cid": "",
    "cmd": 906,
    "cmd_name": "CMD_CHANNEL_PUSH",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "caller_service": "protocol-e2e",
      "channel_id": "news:alerts",
      "content_type": "application/json",
      "event_id": "46cb2fc1-d010-4499-8c84-c323c8093d72",
      "payload": "{\"n\":1}",
      "server_time": 1785909886831
    },
    "route_key": "news:alerts",
    "seq": 0,
    "trace_id": "tr-2376",
    "ts": 1785909886832,
    "ver": 1
  },
  "step": 3
}
```

</details>

### 步骤 5：↑ WS CMD_CHANNEL_UNSUBSCRIBE_REQ（client）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `902` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_902` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `4` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886832` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "client",
  "case": "channel_test/订阅与 publish",
  "direction": "↑ WS CMD_CHANNEL_UNSUBSCRIBE_REQ",
  "note": "↑ WS CMD_CHANNEL_UNSUBSCRIBE_REQ",
  "packet": {
    "cid": "",
    "cmd": 902,
    "cmd_name": "CMD_902",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload_raw_bytes": 13,
    "route_key": "",
    "seq": 4,
    "trace_id": "",
    "ts": 1785909886832,
    "ver": 1
  },
  "step": 5
}
```

</details>

### 步骤 6：↓ WS CMD_CHANNEL_UNSUBSCRIBE_RESP（client）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `903` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_CHANNEL_UNSUBSCRIBE_RESP` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `3` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886834` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `unsubscribed` | `["news:alerts"]` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "client",
  "case": "channel_test/订阅与 publish",
  "direction": "↓ WS CMD_CHANNEL_UNSUBSCRIBE_RESP",
  "note": "↓ WS CMD_CHANNEL_UNSUBSCRIBE_RESP",
  "packet": {
    "cid": "",
    "cmd": 903,
    "cmd_name": "CMD_CHANNEL_UNSUBSCRIBE_RESP",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "unsubscribed": [
        "news:alerts"
      ]
    },
    "route_key": "",
    "seq": 3,
    "trace_id": "",
    "ts": 1785909886834,
    "ver": 1
  },
  "step": 6
}
```

</details>

### 步骤 8：↑ WS CMD_CHANNEL_PUBLISH（client）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `904` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_CHANNEL_PUBLISH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `7` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886834` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `channel_id` | `news:alerts` | 应用通道 ID（namespace:name） |
| `client_event_id` | `` |  |
| `content_type` | `application/json` |  |
| `payload` | `{"client":true}` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "client",
  "case": "channel_test/订阅与 publish",
  "direction": "↑ WS CMD_CHANNEL_PUBLISH",
  "note": "↑ WS CMD_CHANNEL_PUBLISH",
  "packet": {
    "cid": "",
    "cmd": 904,
    "cmd_name": "CMD_CHANNEL_PUBLISH",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "channel_id": "news:alerts",
      "client_event_id": "",
      "content_type": "application/json",
      "payload": "{\"client\":true}"
    },
    "route_key": "",
    "seq": 7,
    "trace_id": "",
    "ts": 1785909886834,
    "ver": 1
  },
  "step": 8
}
```

</details>

### 步骤 9：↓ WS CMD_CHANNEL_PUBLISH_ACK（client）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `905` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_CHANNEL_PUBLISH_ACK` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `4` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886836` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `accepted` | `true` |  |
| `channel_id` | `news:alerts` | 应用通道 ID（namespace:name） |
| `event_id` | `1a7ae425-60d9-4818-bcf9-9f61758a4ee3` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "client",
  "case": "channel_test/订阅与 publish",
  "direction": "↓ WS CMD_CHANNEL_PUBLISH_ACK",
  "note": "↓ WS CMD_CHANNEL_PUBLISH_ACK",
  "packet": {
    "cid": "",
    "cmd": 905,
    "cmd_name": "CMD_CHANNEL_PUBLISH_ACK",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "accepted": "true",
      "channel_id": "news:alerts",
      "event_id": "1a7ae425-60d9-4818-bcf9-9f61758a4ee3"
    },
    "route_key": "",
    "seq": 4,
    "trace_id": "",
    "ts": 1785909886836,
    "ver": 1
  },
  "step": 9
}
```

</details>

---

## cluster_test/跨节点 PUSH 单聊
### 步骤 1：↓ WS CMD_MSG_PUSH (peer 节点)（B）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `cm-2728` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `101` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `p:user_4226:user_868` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `0` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909889601` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `burn_after_read` | `false` |  |
| `burn_ttl_sec` | `0` |  |
| `burned` | `false` |  |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `client_msg_id` | `cm-2728` | 消息级幂等 ID（业务去重） |
| `content` | `cross-node-push` | 消息体；MSG_TEXT 为 UTF-8 文本；MSG_STREAM 为 StreamContent 结构 |
| `conv_id` | `p:user_4226:user_868` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `edit_version` | `0` |  |
| `ext` | `{}` |  |
| `from` | `user_868` | 发送方 user_id |
| `inbox_seq` | `0` |  |
| `msg_id` | `343273120225820672` | 服务端分配的全局消息 ID（雪花） |
| `msg_type` | `MSG_TEXT` | 消息内容类型：MSG_TEXT/MSG_STREAM 等 |
| `priority` | `MSG_PRIORITY_NORMAL` |  |
| `recalled` | `false` |  |
| `server_time` | `1785909889574` | 服务端当前时间（毫秒） |
| `target_users` | `[]` |  |
| `to` | `user_4226` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "B",
  "case": "cluster_test/跨节点 PUSH 单聊",
  "direction": "↓ WS CMD_MSG_PUSH (peer 节点)",
  "note": "↓ WS CMD_MSG_PUSH (peer 节点)",
  "packet": {
    "cid": "cm-2728",
    "cmd": 101,
    "cmd_name": "CMD_MSG_PUSH",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "burn_after_read": "false",
      "burn_ttl_sec": 0,
      "burned": "false",
      "chat_type": "CHAT_PRIVATE",
      "client_msg_id": "cm-2728",
      "content": "cross-node-push",
      "conv_id": "p:user_4226:user_868",
      "conv_seq": 1,
      "edit_version": 0,
      "ext": {},
      "from": "user_868",
      "inbox_seq": 0,
      "msg_id": "343273120225820672",
      "msg_type": "MSG_TEXT",
      "priority": "MSG_PRIORITY_NORMAL",
      "recalled": "false",
      "server_time": 1785909889574,
      "target_users": [],
      "to": "user_4226"
    },
    "route_key": "p:user_4226:user_868",
    "seq": 0,
    "trace_id": "",
    "ts": 1785909889601,
    "ver": 1
  },
  "step": 1
}
```

</details>

---

## cluster_test/跨节点 erpc 转发
### 步骤 1：↓ WS CMD_MSG_ACK_DOWN（A）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `201` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_ACK_DOWN` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `cluster-rk-1` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `2` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909890718` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `client_msg_id` | `cm-3080` | 消息级幂等 ID（业务去重） |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `msg_id` | `343273124927635456` | 服务端分配的全局消息 ID（雪花） |
| `status` | `ACK_SERVER_RECEIVED` | ACK 状态：ACK_SERVER_RECEIVED / ACK_CLIENT_RECEIVED |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "A",
  "case": "cluster_test/跨节点 erpc 转发",
  "direction": "↓ WS CMD_MSG_ACK_DOWN",
  "note": "↓ WS CMD_MSG_ACK_DOWN",
  "packet": {
    "cid": "",
    "cmd": 201,
    "cmd_name": "CMD_MSG_ACK_DOWN",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "client_msg_id": "cm-3080",
      "conv_seq": 1,
      "msg_id": "343273124927635456",
      "status": "ACK_SERVER_RECEIVED"
    },
    "route_key": "cluster-rk-1",
    "seq": 2,
    "trace_id": "",
    "ts": 1785909890718,
    "ver": 1
  },
  "step": 1
}
```

</details>

### 步骤 2：↓ WS CMD_MSG_PUSH (peer)（B）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `cm-3080` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `101` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `p:user_2792:user_2952` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `0` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909890718` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `burn_after_read` | `false` |  |
| `burn_ttl_sec` | `0` |  |
| `burned` | `false` |  |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `client_msg_id` | `cm-3080` | 消息级幂等 ID（业务去重） |
| `content` | `cross-node-erpc` | 消息体；MSG_TEXT 为 UTF-8 文本；MSG_STREAM 为 StreamContent 结构 |
| `conv_id` | `p:user_2792:user_2952` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `edit_version` | `0` |  |
| `ext` | `{}` |  |
| `from` | `user_2792` | 发送方 user_id |
| `inbox_seq` | `0` |  |
| `msg_id` | `343273124927635456` | 服务端分配的全局消息 ID（雪花） |
| `msg_type` | `MSG_TEXT` | 消息内容类型：MSG_TEXT/MSG_STREAM 等 |
| `priority` | `MSG_PRIORITY_NORMAL` |  |
| `recalled` | `false` |  |
| `server_time` | `1785909890693` | 服务端当前时间（毫秒） |
| `target_users` | `[]` |  |
| `to` | `user_2952` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "B",
  "case": "cluster_test/跨节点 erpc 转发",
  "direction": "↓ WS CMD_MSG_PUSH (peer)",
  "note": "↓ WS CMD_MSG_PUSH (peer)",
  "packet": {
    "cid": "cm-3080",
    "cmd": 101,
    "cmd_name": "CMD_MSG_PUSH",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "burn_after_read": "false",
      "burn_ttl_sec": 0,
      "burned": "false",
      "chat_type": "CHAT_PRIVATE",
      "client_msg_id": "cm-3080",
      "content": "cross-node-erpc",
      "conv_id": "p:user_2792:user_2952",
      "conv_seq": 1,
      "edit_version": 0,
      "ext": {},
      "from": "user_2792",
      "inbox_seq": 0,
      "msg_id": "343273124927635456",
      "msg_type": "MSG_TEXT",
      "priority": "MSG_PRIORITY_NORMAL",
      "recalled": "false",
      "server_time": 1785909890693,
      "target_users": [],
      "to": "user_2952"
    },
    "route_key": "p:user_2792:user_2952",
    "seq": 0,
    "trace_id": "",
    "ts": 1785909890718,
    "ver": 1
  },
  "step": 2
}
```

</details>

---

## connection_test/GET metrics
### 步骤 1：↑ HTTP GET /metrics（client）

**HTTP 请求体**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "client",
  "case": "connection_test/GET metrics",
  "direction": "↑ HTTP GET /metrics",
  "http": {
    "request": {},
    "response": {
      "body": "# HELP im_permission_check_count \n# TYPE im_permission_check_count counter\nim_permission_check_count{layer=\"l1\",result=\"allow\",type=\"device_ban\"} 1\nim_permission_check_count{layer=\"pg\",result=\"allow\",…",
      "status": 200
    }
  },
  "note": "↑ HTTP GET /metrics",
  "step": 1
}
```

</details>

---

## connection_test/REST 登录 + WS AUTH + 心跳
### 步骤 1：↑ HTTP POST /api/v1/sessions（client）

**HTTP 请求体**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `app_key` | `app_demo` | 租户应用标识 |
| `device_id` | `d-4775` | 设备唯一标识 |
| `user_id` | `user_2946` | 业务用户 ID |

**HTTP 响应体（节选）**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `access_token` | `du8StgBNsoQXEKknPAhuPnbYlKwD02YUelBiy3jX7SU` | REST 返回的会话 token |
| `clear_local_data` | `false` |  |
| `config` | `{"burn_after_read_enabled":true,"burn_ttl_sec_default":0,"burn_ttl_sec_max":3600,"edit_window_sec":86400,"heartbeat_interval_sec":30,"offline_pull_limit":200,"payload_compression":"none","push_batch_max":50,"recall_window_sec":120}` |  |
| `connection` | `{"preferred_index":0,"websocket_urls":["ws://127.0.0.1:4002/ws"]}` |  |
| `expires_at` | `1785996286215` | token 过期时间（毫秒时间戳） |
| `user_id` | `user_2946` | 业务用户 ID |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "client",
  "case": "connection_test/REST 登录 + WS AUTH + 心跳",
  "direction": "↑ HTTP POST /api/v1/sessions",
  "http": {
    "request": {
      "app_key": "app_demo",
      "device_id": "d-4775",
      "user_id": "user_2946"
    },
    "response": {
      "body": {
        "access_token": "du8StgBNsoQXEKknPAhuPnbYlKwD02YUelBiy3jX7SU",
        "clear_local_data": false,
        "config": {
          "burn_after_read_enabled": true,
          "burn_ttl_sec_default": 0,
          "burn_ttl_sec_max": 3600,
          "edit_window_sec": 86400,
          "heartbeat_interval_sec": 30,
          "offline_pull_limit": 200,
          "payload_compression": "none",
          "push_batch_max": 50,
          "recall_window_sec": 120
        },
        "connection": {
          "preferred_index": 0,
          "websocket_urls": [
            "ws://127.0.0.1:4002/ws"
          ]
        },
        "expires_at": 1785996286215,
        "user_id": "user_2946"
      },
      "status": 200
    }
  },
  "note": "↑ HTTP POST /api/v1/sessions",
  "step": 1
}
```

</details>

### 步骤 3：↑ WS CMD_AUTH_REQ（client）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `1` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_AUTH_REQ` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `2` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886236` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `app_key` | `app_demo` | 租户应用标识 |
| `compression_offered` | `[]` |  |
| `device_id` | `d-4775` | 设备唯一标识 |
| `device_model` | `` |  |
| `device_name` | `` |  |
| `network` | `` |  |
| `os` | `` |  |
| `platform` | `ios` | 客户端平台：ios/android/web/desktop |
| `sdk_ver` | `0.1.0` | SDK 版本号 |
| `token` | `du8StgBNsoQXEKknPAhuPnbYlKwD02YUelBiy3jX7SU` | WS 鉴权 token（与 REST access_token 相同） |
| `user_id` | `user_2946` | 业务用户 ID |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "client",
  "case": "connection_test/REST 登录 + WS AUTH + 心跳",
  "direction": "↑ WS CMD_AUTH_REQ",
  "note": "↑ WS CMD_AUTH_REQ",
  "packet": {
    "cid": "",
    "cmd": 1,
    "cmd_name": "CMD_AUTH_REQ",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "app_key": "app_demo",
      "compression_offered": [],
      "device_id": "d-4775",
      "device_model": "",
      "device_name": "",
      "network": "",
      "os": "",
      "platform": "ios",
      "sdk_ver": "0.1.0",
      "token": "du8StgBNsoQXEKknPAhuPnbYlKwD02YUelBiy3jX7SU",
      "user_id": "user_2946"
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785909886236,
    "ver": 1
  },
  "step": 3
}
```

</details>

### 步骤 4：↓ WS CMD_AUTH_RESP（client）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `2` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_AUTH_RESP` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `1` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886258` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `burn_after_read_enabled` | `true` |  |
| `burn_ttl_sec_default` | `0` |  |
| `burn_ttl_sec_max` | `3600` |  |
| `clear_local_data` | `false` |  |
| `device` | `{"client_ip":"","connected_at":1785909886253,"device_id":"d-4775","device_model":"","device_name":"","network":"","os":"","platform":"loadtest","sdk_ver":"0.1.0","session_id":"7eb3c005-c6a7-4297-9c80-7257c4f7ba9b"}` |  |
| `edit_window_sec` | `86400` |  |
| `heartbeat_interval_sec` | `30` | 心跳间隔（秒） |
| `offline_pull_limit` | `200` |  |
| `payload_compression` | `PAYLOAD_COMPRESSION_NONE` |  |
| `push_batch_max` | `50` |  |
| `recall_window_sec` | `120` |  |
| `server_time` | `1785909886253` | 服务端当前时间（毫秒） |
| `user_id` | `user_2946` | 业务用户 ID |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "client",
  "case": "connection_test/REST 登录 + WS AUTH + 心跳",
  "direction": "↓ WS CMD_AUTH_RESP",
  "note": "↓ WS CMD_AUTH_RESP",
  "packet": {
    "cid": "",
    "cmd": 2,
    "cmd_name": "CMD_AUTH_RESP",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "burn_after_read_enabled": "true",
      "burn_ttl_sec_default": 0,
      "burn_ttl_sec_max": 3600,
      "clear_local_data": "false",
      "device": {
        "client_ip": "",
        "connected_at": 1785909886253,
        "device_id": "d-4775",
        "device_model": "",
        "device_name": "",
        "network": "",
        "os": "",
        "platform": "loadtest",
        "sdk_ver": "0.1.0",
        "session_id": "7eb3c005-c6a7-4297-9c80-7257c4f7ba9b"
      },
      "edit_window_sec": 86400,
      "heartbeat_interval_sec": 30,
      "offline_pull_limit": 200,
      "payload_compression": "PAYLOAD_COMPRESSION_NONE",
      "push_batch_max": 50,
      "recall_window_sec": 120,
      "server_time": 1785909886253,
      "user_id": "user_2946"
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785909886258,
    "ver": 1
  },
  "step": 4
}
```

</details>

### 步骤 6：↑ WS CMD_HEARTBEAT_REQ（client）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `3` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_HEARTBEAT_REQ` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `5` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886271` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `client_time` | `1785909886271` | 客户端本地时间（毫秒） |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "client",
  "case": "connection_test/REST 登录 + WS AUTH + 心跳",
  "direction": "↑ WS CMD_HEARTBEAT_REQ",
  "note": "↑ WS CMD_HEARTBEAT_REQ",
  "packet": {
    "cid": "",
    "cmd": 3,
    "cmd_name": "CMD_HEARTBEAT_REQ",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "client_time": 1785909886271
    },
    "route_key": "",
    "seq": 5,
    "trace_id": "",
    "ts": 1785909886271,
    "ver": 1
  },
  "step": 6
}
```

</details>

### 步骤 7：↓ WS CMD_HEARTBEAT_RESP（client）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `4` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_HEARTBEAT_RESP` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `2` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886270` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `server_time` | `1785909886269` | 服务端当前时间（毫秒） |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "client",
  "case": "connection_test/REST 登录 + WS AUTH + 心跳",
  "direction": "↓ WS CMD_HEARTBEAT_RESP",
  "note": "↓ WS CMD_HEARTBEAT_RESP",
  "packet": {
    "cid": "",
    "cmd": 4,
    "cmd_name": "CMD_HEARTBEAT_RESP",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "server_time": 1785909886269
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785909886270,
    "ver": 1
  },
  "step": 7
}
```

</details>

---

## connection_test/登出 DELETE sessions
### 步骤 1：↑ WS 已鉴权（见 connect_authenticated!）（client）

**HTTP 请求体**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `user_id` | `user_267` | 业务用户 ID |

**HTTP 响应体（节选）**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `status` | `authenticated` | ACK 状态：ACK_SERVER_RECEIVED / ACK_CLIENT_RECEIVED |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "client",
  "case": "connection_test/登出 DELETE sessions",
  "direction": "↑ WS 已鉴权（见 connect_authenticated!）",
  "http": {
    "request": {
      "user_id": "user_267"
    },
    "response": {
      "status": "authenticated"
    }
  },
  "note": "↑ WS 已鉴权（见 connect_authenticated!）",
  "step": 1
}
```

</details>

### 步骤 2：↑ HTTP DELETE /api/v1/sessions/current（client）

**HTTP 请求体**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `token` | `Bearer …` | WS 鉴权 token（与 REST access_token 相同） |

**HTTP 响应体（节选）**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `status` | `204` | ACK 状态：ACK_SERVER_RECEIVED / ACK_CLIENT_RECEIVED |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "client",
  "case": "connection_test/登出 DELETE sessions",
  "direction": "↑ HTTP DELETE /api/v1/sessions/current",
  "http": {
    "request": {
      "token": "Bearer …"
    },
    "response": {
      "status": 204
    }
  },
  "note": "↑ HTTP DELETE /api/v1/sessions/current",
  "step": 2
}
```

</details>

---

## conversation_test/REST 会话列表未读与已读同步
### 步骤 2：↑ WS CMD_MSG_SEND（A）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `100` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_SEND` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `1` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886763` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `message` | `{"burn_after_read":"false","burn_ttl_sec":0,"burned":"false","chat_type":"CHAT_PRIVATE","client_msg_id":"conv-2248","content":"list-preview","conv_id":"","conv_seq":0,"edit_version":0,"ext":{},"from":"user_1928","inbox_seq":0,"msg_id":"","msg_type":"MSG_TEXT","priority":"MSG_PRIORITY_NORMAL","recalled":"false","server_time":0,"target_users":[],"to":"user_2088"}` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "A",
  "case": "conversation_test/REST 会话列表未读与已读同步",
  "direction": "↑ WS CMD_MSG_SEND",
  "note": "↑ WS CMD_MSG_SEND",
  "packet": {
    "cid": "",
    "cmd": 100,
    "cmd_name": "CMD_MSG_SEND",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "message": {
        "burn_after_read": "false",
        "burn_ttl_sec": 0,
        "burned": "false",
        "chat_type": "CHAT_PRIVATE",
        "client_msg_id": "conv-2248",
        "content": "list-preview",
        "conv_id": "",
        "conv_seq": 0,
        "edit_version": 0,
        "ext": {},
        "from": "user_1928",
        "inbox_seq": 0,
        "msg_id": "",
        "msg_type": "MSG_TEXT",
        "priority": "MSG_PRIORITY_NORMAL",
        "recalled": "false",
        "server_time": 0,
        "target_users": [],
        "to": "user_2088"
      }
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785909886763,
    "ver": 1
  },
  "step": 2
}
```

</details>

### 步骤 3：↓ WS CMD_MSG_ACK_DOWN（A）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `201` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_ACK_DOWN` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `2` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886773` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `client_msg_id` | `conv-2248` | 消息级幂等 ID（业务去重） |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `msg_id` | `343273108469186560` | 服务端分配的全局消息 ID（雪花） |
| `status` | `ACK_SERVER_RECEIVED` | ACK 状态：ACK_SERVER_RECEIVED / ACK_CLIENT_RECEIVED |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "A",
  "case": "conversation_test/REST 会话列表未读与已读同步",
  "direction": "↓ WS CMD_MSG_ACK_DOWN",
  "note": "↓ WS CMD_MSG_ACK_DOWN",
  "packet": {
    "cid": "",
    "cmd": 201,
    "cmd_name": "CMD_MSG_ACK_DOWN",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "client_msg_id": "conv-2248",
      "conv_seq": 1,
      "msg_id": "343273108469186560",
      "status": "ACK_SERVER_RECEIVED"
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785909886773,
    "ver": 1
  },
  "step": 3
}
```

</details>

### 步骤 4：↓ WS CMD_MSG_PUSH（B）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `conv-2248` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `101` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `p:user_1928:user_2088` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `0` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886773` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `burn_after_read` | `false` |  |
| `burn_ttl_sec` | `0` |  |
| `burned` | `false` |  |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `client_msg_id` | `conv-2248` | 消息级幂等 ID（业务去重） |
| `content` | `list-preview` | 消息体；MSG_TEXT 为 UTF-8 文本；MSG_STREAM 为 StreamContent 结构 |
| `conv_id` | `p:user_1928:user_2088` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `edit_version` | `0` |  |
| `ext` | `{}` |  |
| `from` | `user_1928` | 发送方 user_id |
| `inbox_seq` | `0` |  |
| `msg_id` | `343273108469186560` | 服务端分配的全局消息 ID（雪花） |
| `msg_type` | `MSG_TEXT` | 消息内容类型：MSG_TEXT/MSG_STREAM 等 |
| `priority` | `MSG_PRIORITY_NORMAL` |  |
| `recalled` | `false` |  |
| `server_time` | `1785909886767` | 服务端当前时间（毫秒） |
| `target_users` | `[]` |  |
| `to` | `user_2088` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "B",
  "case": "conversation_test/REST 会话列表未读与已读同步",
  "direction": "↓ WS CMD_MSG_PUSH",
  "note": "↓ WS CMD_MSG_PUSH",
  "packet": {
    "cid": "conv-2248",
    "cmd": 101,
    "cmd_name": "CMD_MSG_PUSH",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "burn_after_read": "false",
      "burn_ttl_sec": 0,
      "burned": "false",
      "chat_type": "CHAT_PRIVATE",
      "client_msg_id": "conv-2248",
      "content": "list-preview",
      "conv_id": "p:user_1928:user_2088",
      "conv_seq": 1,
      "edit_version": 0,
      "ext": {},
      "from": "user_1928",
      "inbox_seq": 0,
      "msg_id": "343273108469186560",
      "msg_type": "MSG_TEXT",
      "priority": "MSG_PRIORITY_NORMAL",
      "recalled": "false",
      "server_time": 1785909886767,
      "target_users": [],
      "to": "user_2088"
    },
    "route_key": "p:user_1928:user_2088",
    "seq": 0,
    "trace_id": "",
    "ts": 1785909886773,
    "ver": 1
  },
  "step": 4
}
```

</details>

### 步骤 5：↑ HTTP GET /api/v1/conversations（B）

**HTTP 请求体**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `limit` | `20` | 离线拉取条数上限 |

**HTTP 响应体（节选）**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `conversations` | `[{"chat_type":1,"conv_id":"p:user_1928:user_2088","last_msg_id":"343273108469186560","last_msg_preview":"list-preview","last_msg_seq":1,"last_msg_time":1785909886767,"last_msg_type":1,"last_read_conv_seq":0,"peer_id":"user_1928","unread_count":1}]` |  |
| `total_unread` | `1` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "B",
  "case": "conversation_test/REST 会话列表未读与已读同步",
  "direction": "↑ HTTP GET /api/v1/conversations",
  "http": {
    "request": {
      "limit": 20
    },
    "response": {
      "body": {
        "conversations": [
          {
            "chat_type": 1,
            "conv_id": "p:user_1928:user_2088",
            "last_msg_id": "343273108469186560",
            "last_msg_preview": "list-preview",
            "last_msg_seq": 1,
            "last_msg_time": 1785909886767,
            "last_msg_type": 1,
            "last_read_conv_seq": 0,
            "peer_id": "user_1928",
            "unread_count": 1
          }
        ],
        "total_unread": 1
      },
      "status": 200
    }
  },
  "note": "↑ HTTP GET /api/v1/conversations",
  "step": 5
}
```

</details>

### 步骤 7：↑ WS CMD_MSG_READ（B）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `202` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_READ` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `6` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886778` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `conv_id` | `p:user_1928:user_2088` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `from` | `user_2088` | 发送方 user_id |
| `msg_id` | `343273108469186560` | 服务端分配的全局消息 ID（雪花） |
| `timestamp` | `0` |  |
| `to` | `user_1928` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |
| `unread_count` | `` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "B",
  "case": "conversation_test/REST 会话列表未读与已读同步",
  "direction": "↑ WS CMD_MSG_READ",
  "note": "↑ WS CMD_MSG_READ",
  "packet": {
    "cid": "",
    "cmd": 202,
    "cmd_name": "CMD_MSG_READ",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "chat_type": "CHAT_PRIVATE",
      "conv_id": "p:user_1928:user_2088",
      "conv_seq": 1,
      "from": "user_2088",
      "msg_id": "343273108469186560",
      "timestamp": 0,
      "to": "user_1928",
      "unread_count": null
    },
    "route_key": "",
    "seq": 6,
    "trace_id": "",
    "ts": 1785909886778,
    "ver": 1
  },
  "step": 7
}
```

</details>

### 步骤 8：↓ WS CMD_MSG_READ (对端已读)（A）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `202` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_READ` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `p:user_1928:user_2088` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `0` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886779` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `conv_id` | `p:user_1928:user_2088` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `from` | `user_2088` | 发送方 user_id |
| `msg_id` | `343273108469186560` | 服务端分配的全局消息 ID（雪花） |
| `timestamp` | `1785909886779` |  |
| `to` | `user_1928` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |
| `unread_count` | `0` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "A",
  "case": "conversation_test/REST 会话列表未读与已读同步",
  "direction": "↓ WS CMD_MSG_READ (对端已读)",
  "note": "↓ WS CMD_MSG_READ (对端已读)",
  "packet": {
    "cid": "",
    "cmd": 202,
    "cmd_name": "CMD_MSG_READ",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "chat_type": "CHAT_PRIVATE",
      "conv_id": "p:user_1928:user_2088",
      "conv_seq": 1,
      "from": "user_2088",
      "msg_id": "343273108469186560",
      "timestamp": 1785909886779,
      "to": "user_1928",
      "unread_count": 0
    },
    "route_key": "p:user_1928:user_2088",
    "seq": 0,
    "trace_id": "",
    "ts": 1785909886779,
    "ver": 1
  },
  "step": 8
}
```

</details>

### 步骤 9：↑ HTTP GET /api/v1/conversations (after read)（A）

**HTTP 请求体**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `limit` | `20` | 离线拉取条数上限 |

**HTTP 响应体（节选）**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `conversations` | `[{"chat_type":1,"conv_id":"p:user_1928:user_2088","last_msg_id":"343273108469186560","last_msg_preview":"list-preview","last_msg_seq":1,"last_msg_time":1785909886767,"last_msg_type":1,"last_read_conv_seq":1,"peer_id":"user_1928","unread_count":0}]` |  |
| `total_unread` | `0` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "A",
  "case": "conversation_test/REST 会话列表未读与已读同步",
  "direction": "↑ HTTP GET /api/v1/conversations (after read)",
  "http": {
    "request": {
      "limit": 20
    },
    "response": {
      "body": {
        "conversations": [
          {
            "chat_type": 1,
            "conv_id": "p:user_1928:user_2088",
            "last_msg_id": "343273108469186560",
            "last_msg_preview": "list-preview",
            "last_msg_seq": 1,
            "last_msg_time": 1785909886767,
            "last_msg_type": 1,
            "last_read_conv_seq": 1,
            "peer_id": "user_1928",
            "unread_count": 0
          }
        ],
        "total_unread": 0
      },
      "status": 200
    }
  },
  "note": "↑ HTTP GET /api/v1/conversations (after read)",
  "step": 9
}
```

</details>

---

## conversation_test/群聊会话列表未读
### 步骤 1：↓ WS CMD_GROUP_CREATE_RESP（owner）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `601` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_GROUP_CREATE_RESP` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `2` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886807` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `conv_id` | `g:gc-4066` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `created_at` | `1785909886805` |  |
| `group_id` | `gc-4066` | 群 ID |
| `name` | `conv-g` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "owner",
  "case": "conversation_test/群聊会话列表未读",
  "direction": "↓ WS CMD_GROUP_CREATE_RESP",
  "note": "↓ WS CMD_GROUP_CREATE_RESP",
  "packet": {
    "cid": "",
    "cmd": 601,
    "cmd_name": "CMD_GROUP_CREATE_RESP",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "conv_id": "g:gc-4066",
      "created_at": 1785909886805,
      "group_id": "gc-4066",
      "name": "conv-g"
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785909886807,
    "ver": 1
  },
  "step": 1
}
```

</details>

### 步骤 2：↓ WS CMD_MSG_ACK_DOWN（owner）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `201` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_ACK_DOWN` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `3` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886816` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `client_msg_id` | `gcm-2312` | 消息级幂等 ID（业务去重） |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `msg_id` | `343273108653735936` | 服务端分配的全局消息 ID（雪花） |
| `status` | `ACK_SERVER_RECEIVED` | ACK 状态：ACK_SERVER_RECEIVED / ACK_CLIENT_RECEIVED |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "owner",
  "case": "conversation_test/群聊会话列表未读",
  "direction": "↓ WS CMD_MSG_ACK_DOWN",
  "note": "↓ WS CMD_MSG_ACK_DOWN",
  "packet": {
    "cid": "",
    "cmd": 201,
    "cmd_name": "CMD_MSG_ACK_DOWN",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "client_msg_id": "gcm-2312",
      "conv_seq": 1,
      "msg_id": "343273108653735936",
      "status": "ACK_SERVER_RECEIVED"
    },
    "route_key": "",
    "seq": 3,
    "trace_id": "",
    "ts": 1785909886816,
    "ver": 1
  },
  "step": 2
}
```

</details>

### 步骤 3：↑ HTTP GET /api/v1/conversations (group)（owner）

**HTTP 请求体**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `limit` | `20` | 离线拉取条数上限 |

**HTTP 响应体（节选）**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `conversations` | `[{"chat_type":2,"conv_id":"g:gc-4066","last_msg_id":"343273108653735936","last_msg_preview":"group-unread","last_msg_seq":1,"last_msg_time":1785909886810,"last_msg_type":1,"last_read_conv_seq":0,"peer_id":"gc-4066","unread_count":1}]` |  |
| `total_unread` | `1` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "owner",
  "case": "conversation_test/群聊会话列表未读",
  "direction": "↑ HTTP GET /api/v1/conversations (group)",
  "http": {
    "request": {
      "limit": 20
    },
    "response": {
      "body": {
        "conversations": [
          {
            "chat_type": 2,
            "conv_id": "g:gc-4066",
            "last_msg_id": "343273108653735936",
            "last_msg_preview": "group-unread",
            "last_msg_seq": 1,
            "last_msg_time": 1785909886810,
            "last_msg_type": 1,
            "last_read_conv_seq": 0,
            "peer_id": "gc-4066",
            "unread_count": 1
          }
        ],
        "total_unread": 1
      },
      "status": 200
    }
  },
  "note": "↑ HTTP GET /api/v1/conversations (group)",
  "step": 3
}
```

</details>

---

## extensions_test/已读回执
### 步骤 2：↑ WS CMD_MSG_READ（B）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `202` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_READ` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `1` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886662` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `conv_id` | `p:user_1416:user_7239` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `from` | `user_1416` | 发送方 user_id |
| `msg_id` | `343273108003618816` | 服务端分配的全局消息 ID（雪花） |
| `timestamp` | `0` |  |
| `to` | `user_7239` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |
| `unread_count` | `` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "B",
  "case": "extensions_test/已读回执",
  "direction": "↑ WS CMD_MSG_READ",
  "note": "↑ WS CMD_MSG_READ",
  "packet": {
    "cid": "",
    "cmd": 202,
    "cmd_name": "CMD_MSG_READ",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "chat_type": "CHAT_PRIVATE",
      "conv_id": "p:user_1416:user_7239",
      "conv_seq": 1,
      "from": "user_1416",
      "msg_id": "343273108003618816",
      "timestamp": 0,
      "to": "user_7239",
      "unread_count": null
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785909886662,
    "ver": 1
  },
  "step": 2
}
```

</details>

### 步骤 3：↓ WS CMD_MSG_READ (对端已读)（A）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `202` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_READ` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `p:user_1416:user_7239` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `0` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886664` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `conv_id` | `p:user_1416:user_7239` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `from` | `user_1416` | 发送方 user_id |
| `msg_id` | `343273108003618816` | 服务端分配的全局消息 ID（雪花） |
| `timestamp` | `1785909886663` |  |
| `to` | `user_7239` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |
| `unread_count` | `0` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "A",
  "case": "extensions_test/已读回执",
  "direction": "↓ WS CMD_MSG_READ (对端已读)",
  "note": "↓ WS CMD_MSG_READ (对端已读)",
  "packet": {
    "cid": "",
    "cmd": 202,
    "cmd_name": "CMD_MSG_READ",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "chat_type": "CHAT_PRIVATE",
      "conv_id": "p:user_1416:user_7239",
      "conv_seq": 1,
      "from": "user_1416",
      "msg_id": "343273108003618816",
      "timestamp": 1785909886663,
      "to": "user_7239",
      "unread_count": 0
    },
    "route_key": "p:user_1416:user_7239",
    "seq": 0,
    "trace_id": "",
    "ts": 1785909886664,
    "ver": 1
  },
  "step": 3
}
```

</details>

---

## extensions_test/撤回消息
### 步骤 1：↓ WS CMD_MSG_RECALL_PUSH（A）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `401` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_RECALL_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `3` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886693` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `conv_id` | `p:user_1480:user_7303` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `from` | `user_7303` | 发送方 user_id |
| `msg_id` | `343273108112670720` | 服务端分配的全局消息 ID（雪花） |
| `reason` | `mistake` | 踢下线/撤回等原因 |
| `timestamp` | `1785909886693` |  |
| `to` | `user_1480` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "A",
  "case": "extensions_test/撤回消息",
  "direction": "↓ WS CMD_MSG_RECALL_PUSH",
  "note": "↓ WS CMD_MSG_RECALL_PUSH",
  "packet": {
    "cid": "",
    "cmd": 401,
    "cmd_name": "CMD_MSG_RECALL_PUSH",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "chat_type": "CHAT_PRIVATE",
      "conv_id": "p:user_1480:user_7303",
      "from": "user_7303",
      "msg_id": "343273108112670720",
      "reason": "mistake",
      "timestamp": 1785909886693,
      "to": "user_1480"
    },
    "route_key": "",
    "seq": 3,
    "trace_id": "",
    "ts": 1785909886693,
    "ver": 1
  },
  "step": 1
}
```

</details>

### 步骤 2：↓ WS CMD_MSG_RECALL_PUSH (对端)（B）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `401` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_RECALL_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `p:user_1480:user_7303` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `0` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886693` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `conv_id` | `p:user_1480:user_7303` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `from` | `user_7303` | 发送方 user_id |
| `msg_id` | `343273108112670720` | 服务端分配的全局消息 ID（雪花） |
| `reason` | `mistake` | 踢下线/撤回等原因 |
| `timestamp` | `1785909886693` |  |
| `to` | `user_1480` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "B",
  "case": "extensions_test/撤回消息",
  "direction": "↓ WS CMD_MSG_RECALL_PUSH (对端)",
  "note": "↓ WS CMD_MSG_RECALL_PUSH (对端)",
  "packet": {
    "cid": "",
    "cmd": 401,
    "cmd_name": "CMD_MSG_RECALL_PUSH",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "chat_type": "CHAT_PRIVATE",
      "conv_id": "p:user_1480:user_7303",
      "from": "user_7303",
      "msg_id": "343273108112670720",
      "reason": "mistake",
      "timestamp": 1785909886693,
      "to": "user_1480"
    },
    "route_key": "p:user_1480:user_7303",
    "seq": 0,
    "trace_id": "",
    "ts": 1785909886693,
    "ver": 1
  },
  "step": 2
}
```

</details>

---

## extensions_test/编辑消息
### 步骤 1：↓ WS CMD_MSG_EDIT_PUSH（A）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `403` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_EDIT_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `3` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886721` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `content` | `edited` | 消息体；MSG_TEXT 为 UTF-8 文本；MSG_STREAM 为 StreamContent 结构 |
| `conv_id` | `p:user_1704:user_3778` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `edit_version` | `1` |  |
| `ext` | `{}` |  |
| `from` | `user_3778` | 发送方 user_id |
| `msg_id` | `343273108234305536` | 服务端分配的全局消息 ID（雪花） |
| `msg_type` | `MSG_TEXT` | 消息内容类型：MSG_TEXT/MSG_STREAM 等 |
| `timestamp` | `1785909886721` |  |
| `to` | `user_1704` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "A",
  "case": "extensions_test/编辑消息",
  "direction": "↓ WS CMD_MSG_EDIT_PUSH",
  "note": "↓ WS CMD_MSG_EDIT_PUSH",
  "packet": {
    "cid": "",
    "cmd": 403,
    "cmd_name": "CMD_MSG_EDIT_PUSH",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "chat_type": "CHAT_PRIVATE",
      "content": "edited",
      "conv_id": "p:user_1704:user_3778",
      "edit_version": 1,
      "ext": {},
      "from": "user_3778",
      "msg_id": "343273108234305536",
      "msg_type": "MSG_TEXT",
      "timestamp": 1785909886721,
      "to": "user_1704"
    },
    "route_key": "",
    "seq": 3,
    "trace_id": "",
    "ts": 1785909886721,
    "ver": 1
  },
  "step": 1
}
```

</details>

---

## extensions_test/透传指令
### 步骤 2：↑ WS CMD_PASSTHROUGH（A）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `0` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_0` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `1` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886637` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "A",
  "case": "extensions_test/透传指令",
  "direction": "↑ WS CMD_PASSTHROUGH",
  "note": "↑ WS CMD_PASSTHROUGH",
  "packet": {
    "cid": "",
    "cmd": 0,
    "cmd_name": "CMD_0",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload_raw_bytes": 49,
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785909886637,
    "ver": 1
  },
  "step": 2
}
```

</details>

### 步骤 3：↓ WS CMD_PASSTHROUGH（B）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `500` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_PASSTHROUGH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `0` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886639` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `action` | `typing` | 透传 action 名 |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `conv_id` | `` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `data` | `{"typing":true}` | 透传 JSON 字符串 |
| `from` | `user_1352` | 发送方 user_id |
| `persist` | `false` |  |
| `to` | `user_1189` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |
| `ttl_sec` | `0` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "B",
  "case": "extensions_test/透传指令",
  "direction": "↓ WS CMD_PASSTHROUGH",
  "note": "↓ WS CMD_PASSTHROUGH",
  "packet": {
    "cid": "",
    "cmd": 500,
    "cmd_name": "CMD_PASSTHROUGH",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "action": "typing",
      "chat_type": "CHAT_PRIVATE",
      "conv_id": "",
      "data": "{\"typing\":true}",
      "from": "user_1352",
      "persist": "false",
      "to": "user_1189",
      "ttl_sec": 0
    },
    "route_key": "",
    "seq": 0,
    "trace_id": "",
    "ts": 1785909886639,
    "ver": 1
  },
  "step": 3
}
```

</details>

---

## extensions_test/阅后即焚：已读后双方收到 BURN_PUSH
### 步骤 1：↓ WS CMD_MSG_ACK_DOWN（A）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `201` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_ACK_DOWN` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `2` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886595` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `client_msg_id` | `94bb6161a93d79d1` | 消息级幂等 ID（业务去重） |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `msg_id` | `343273107730989056` | 服务端分配的全局消息 ID（雪花） |
| `status` | `ACK_SERVER_RECEIVED` | ACK 状态：ACK_SERVER_RECEIVED / ACK_CLIENT_RECEIVED |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "A",
  "case": "extensions_test/阅后即焚：已读后双方收到 BURN_PUSH",
  "direction": "↓ WS CMD_MSG_ACK_DOWN",
  "note": "↓ WS CMD_MSG_ACK_DOWN",
  "packet": {
    "cid": "",
    "cmd": 201,
    "cmd_name": "CMD_MSG_ACK_DOWN",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "client_msg_id": "94bb6161a93d79d1",
      "conv_seq": 1,
      "msg_id": "343273107730989056",
      "status": "ACK_SERVER_RECEIVED"
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785909886595,
    "ver": 1
  },
  "step": 1
}
```

</details>

### 步骤 2：↓ WS CMD_MSG_PUSH（B）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `94bb6161a93d79d1` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `101` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `p:user_1029:user_3266` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `0` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886595` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `burn_after_read` | `true` |  |
| `burn_ttl_sec` | `0` |  |
| `burned` | `false` |  |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `client_msg_id` | `94bb6161a93d79d1` | 消息级幂等 ID（业务去重） |
| `content` | `secret` | 消息体；MSG_TEXT 为 UTF-8 文本；MSG_STREAM 为 StreamContent 结构 |
| `conv_id` | `p:user_1029:user_3266` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `edit_version` | `0` |  |
| `ext` | `{}` |  |
| `from` | `user_1029` | 发送方 user_id |
| `inbox_seq` | `0` |  |
| `msg_id` | `343273107730989056` | 服务端分配的全局消息 ID（雪花） |
| `msg_type` | `MSG_TEXT` | 消息内容类型：MSG_TEXT/MSG_STREAM 等 |
| `priority` | `MSG_PRIORITY_NORMAL` |  |
| `recalled` | `false` |  |
| `server_time` | `1785909886590` | 服务端当前时间（毫秒） |
| `target_users` | `[]` |  |
| `to` | `user_3266` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "B",
  "case": "extensions_test/阅后即焚：已读后双方收到 BURN_PUSH",
  "direction": "↓ WS CMD_MSG_PUSH",
  "note": "↓ WS CMD_MSG_PUSH",
  "packet": {
    "cid": "94bb6161a93d79d1",
    "cmd": 101,
    "cmd_name": "CMD_MSG_PUSH",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "burn_after_read": "true",
      "burn_ttl_sec": 0,
      "burned": "false",
      "chat_type": "CHAT_PRIVATE",
      "client_msg_id": "94bb6161a93d79d1",
      "content": "secret",
      "conv_id": "p:user_1029:user_3266",
      "conv_seq": 1,
      "edit_version": 0,
      "ext": {},
      "from": "user_1029",
      "inbox_seq": 0,
      "msg_id": "343273107730989056",
      "msg_type": "MSG_TEXT",
      "priority": "MSG_PRIORITY_NORMAL",
      "recalled": "false",
      "server_time": 1785909886590,
      "target_users": [],
      "to": "user_3266"
    },
    "route_key": "p:user_1029:user_3266",
    "seq": 0,
    "trace_id": "",
    "ts": 1785909886595,
    "ver": 1
  },
  "step": 2
}
```

</details>

### 步骤 4：↑ WS CMD_MSG_READ（B）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `202` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_READ` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `3` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886596` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `conv_id` | `p:user_1029:user_3266` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `from` | `user_3266` | 发送方 user_id |
| `msg_id` | `343273107730989056` | 服务端分配的全局消息 ID（雪花） |
| `timestamp` | `0` |  |
| `to` | `user_1029` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |
| `unread_count` | `` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "B",
  "case": "extensions_test/阅后即焚：已读后双方收到 BURN_PUSH",
  "direction": "↑ WS CMD_MSG_READ",
  "note": "↑ WS CMD_MSG_READ",
  "packet": {
    "cid": "",
    "cmd": 202,
    "cmd_name": "CMD_MSG_READ",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "chat_type": "CHAT_PRIVATE",
      "conv_id": "p:user_1029:user_3266",
      "conv_seq": 1,
      "from": "user_3266",
      "msg_id": "343273107730989056",
      "timestamp": 0,
      "to": "user_1029",
      "unread_count": null
    },
    "route_key": "",
    "seq": 3,
    "trace_id": "",
    "ts": 1785909886596,
    "ver": 1
  },
  "step": 4
}
```

</details>

### 步骤 5：↓ WS CMD_MSG_BURN_PUSH（A）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `404` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_BURN_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `p:user_1029:user_3266` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `0` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886612` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `burn_ttl_sec` | `0` |  |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `conv_id` | `p:user_1029:user_3266` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `from` | `user_1029` | 发送方 user_id |
| `msg_id` | `343273107730989056` | 服务端分配的全局消息 ID（雪花） |
| `timestamp` | `1785909886611` |  |
| `to` | `user_3266` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "A",
  "case": "extensions_test/阅后即焚：已读后双方收到 BURN_PUSH",
  "direction": "↓ WS CMD_MSG_BURN_PUSH",
  "note": "↓ WS CMD_MSG_BURN_PUSH",
  "packet": {
    "cid": "",
    "cmd": 404,
    "cmd_name": "CMD_MSG_BURN_PUSH",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "burn_ttl_sec": 0,
      "chat_type": "CHAT_PRIVATE",
      "conv_id": "p:user_1029:user_3266",
      "from": "user_1029",
      "msg_id": "343273107730989056",
      "timestamp": 1785909886611,
      "to": "user_3266"
    },
    "route_key": "p:user_1029:user_3266",
    "seq": 0,
    "trace_id": "",
    "ts": 1785909886612,
    "ver": 1
  },
  "step": 5
}
```

</details>

---

## friend_policy_test/require_friend_to_send
### 步骤 1：↓ WS CMD_ERROR (非好友)（A）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `6` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_ERROR` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `2` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886332` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `code` | `CODE_FRIEND_NOT_FRIEND` | ErrorCode 枚举值 |
| `msg` | `friendship required` | 人类可读错误说明 |
| `ref_cid` | `` |  |
| `ref_cmd` | `100` | 引发错误的原始请求 cmd |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "A",
  "case": "friend_policy_test/require_friend_to_send",
  "direction": "↓ WS CMD_ERROR (非好友)",
  "note": "↓ WS CMD_ERROR (非好友)",
  "packet": {
    "cid": "",
    "cmd": 6,
    "cmd_name": "CMD_ERROR",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "code": "CODE_FRIEND_NOT_FRIEND",
      "msg": "friendship required",
      "ref_cid": "",
      "ref_cmd": 100
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785909886332,
    "ver": 1
  },
  "step": 1
}
```

</details>

### 步骤 2：↓ WS CMD_FRIEND_ADD_RESP（A）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `801` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_FRIEND_ADD_RESP` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `3` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886341` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `request_id` | `fr872` | 好友请求 ID |
| `status` | `FRIEND_STATUS_PENDING` | ACK 状态：ACK_SERVER_RECEIVED / ACK_CLIENT_RECEIVED |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "A",
  "case": "friend_policy_test/require_friend_to_send",
  "direction": "↓ WS CMD_FRIEND_ADD_RESP",
  "note": "↓ WS CMD_FRIEND_ADD_RESP",
  "packet": {
    "cid": "",
    "cmd": 801,
    "cmd_name": "CMD_FRIEND_ADD_RESP",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "request_id": "fr872",
      "status": "FRIEND_STATUS_PENDING"
    },
    "route_key": "",
    "seq": 3,
    "trace_id": "",
    "ts": 1785909886341,
    "ver": 1
  },
  "step": 2
}
```

</details>

### 步骤 4：↑ WS CMD_FRIEND_ACCEPT_REQ（B）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `0` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_0` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `3` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886343` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "B",
  "case": "friend_policy_test/require_friend_to_send",
  "direction": "↑ WS CMD_FRIEND_ACCEPT_REQ",
  "note": "↑ WS CMD_FRIEND_ACCEPT_REQ",
  "packet": {
    "cid": "",
    "cmd": 0,
    "cmd_name": "CMD_0",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload_raw_bytes": 17,
    "route_key": "",
    "seq": 3,
    "trace_id": "",
    "ts": 1785909886343,
    "ver": 1
  },
  "step": 4
}
```

</details>

### 步骤 5：↓ WS CMD_FRIEND_ACCEPT_RESP（B）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `804` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_FRIEND_ACCEPT_RESP` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `2` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886347` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `friend_user_id` | `user_264` |  |
| `status` | `FRIEND_STATUS_ACCEPTED` | ACK 状态：ACK_SERVER_RECEIVED / ACK_CLIENT_RECEIVED |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "B",
  "case": "friend_policy_test/require_friend_to_send",
  "direction": "↓ WS CMD_FRIEND_ACCEPT_RESP",
  "note": "↓ WS CMD_FRIEND_ACCEPT_RESP",
  "packet": {
    "cid": "",
    "cmd": 804,
    "cmd_name": "CMD_FRIEND_ACCEPT_RESP",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "friend_user_id": "user_264",
      "status": "FRIEND_STATUS_ACCEPTED"
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785909886347,
    "ver": 1
  },
  "step": 5
}
```

</details>

---

## friend_test/好友请求列表
### 步骤 2：↑ WS CMD_FRIEND_REQUEST_LIST_REQ（B）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `821` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_821` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `1` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886485` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "B",
  "case": "friend_test/好友请求列表",
  "direction": "↑ WS CMD_FRIEND_REQUEST_LIST_REQ",
  "note": "↑ WS CMD_FRIEND_REQUEST_LIST_REQ",
  "packet": {
    "cid": "",
    "cmd": 821,
    "cmd_name": "CMD_821",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload_raw_bytes": 2,
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785909886485,
    "ver": 1
  },
  "step": 2
}
```

</details>

### 步骤 3：↓ WS CMD_FRIEND_REQUEST_LIST_RESP（B）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `822` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_FRIEND_REQUEST_LIST_RESP` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `2` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886488` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `has_more` | `false` |  |
| `next_cursor` | `` |  |
| `requests` | `[{"from_avatar":"","from_nickname":"","from_user_id":"user_1224","message":"","request_id":"fr1318","status":"FRIEND_REQUEST_STATUS_PENDING","timestamp":1785909886482,"to_avatar":"","to_nickname":"","to_user_id":"user_1158"}]` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "B",
  "case": "friend_test/好友请求列表",
  "direction": "↓ WS CMD_FRIEND_REQUEST_LIST_RESP",
  "note": "↓ WS CMD_FRIEND_REQUEST_LIST_RESP",
  "packet": {
    "cid": "",
    "cmd": 822,
    "cmd_name": "CMD_FRIEND_REQUEST_LIST_RESP",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "has_more": "false",
      "next_cursor": "",
      "requests": [
        {
          "from_avatar": "",
          "from_nickname": "",
          "from_user_id": "user_1224",
          "message": "",
          "request_id": "fr1318",
          "status": "FRIEND_REQUEST_STATUS_PENDING",
          "timestamp": 1785909886482,
          "to_avatar": "",
          "to_nickname": "",
          "to_user_id": "user_1158"
        }
      ]
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785909886488,
    "ver": 1
  },
  "step": 3
}
```

</details>

---

## friend_test/拉黑与取消拉黑
### 步骤 1：↓ WS CMD_FRIEND_BLOCK_RESP（A）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `813` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_FRIEND_BLOCK_RESP` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `2` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886537` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `user_id` | `user_1288` | 业务用户 ID |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "A",
  "case": "friend_test/拉黑与取消拉黑",
  "direction": "↓ WS CMD_FRIEND_BLOCK_RESP",
  "note": "↓ WS CMD_FRIEND_BLOCK_RESP",
  "packet": {
    "cid": "",
    "cmd": 813,
    "cmd_name": "CMD_FRIEND_BLOCK_RESP",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "user_id": "user_1288"
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785909886537,
    "ver": 1
  },
  "step": 1
}
```

</details>

### 步骤 2：↓ WS CMD_ERROR (拉黑后发消息)（A）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `6` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_ERROR` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `3` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886538` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `code` | `CODE_FRIEND_BLOCKED` | ErrorCode 枚举值 |
| `msg` | `you blocked peer` | 人类可读错误说明 |
| `ref_cid` | `` |  |
| `ref_cmd` | `100` | 引发错误的原始请求 cmd |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "A",
  "case": "friend_test/拉黑与取消拉黑",
  "direction": "↓ WS CMD_ERROR (拉黑后发消息)",
  "note": "↓ WS CMD_ERROR (拉黑后发消息)",
  "packet": {
    "cid": "",
    "cmd": 6,
    "cmd_name": "CMD_ERROR",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "code": "CODE_FRIEND_BLOCKED",
      "msg": "you blocked peer",
      "ref_cid": "",
      "ref_cmd": 100
    },
    "route_key": "",
    "seq": 3,
    "trace_id": "",
    "ts": 1785909886538,
    "ver": 1
  },
  "step": 2
}
```

</details>

### 步骤 3：↓ WS CMD_FRIEND_UNBLOCK_RESP（A）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `816` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_FRIEND_UNBLOCK_RESP` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `4` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886541` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `user_id` | `user_1288` | 业务用户 ID |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "A",
  "case": "friend_test/拉黑与取消拉黑",
  "direction": "↓ WS CMD_FRIEND_UNBLOCK_RESP",
  "note": "↓ WS CMD_FRIEND_UNBLOCK_RESP",
  "packet": {
    "cid": "",
    "cmd": 816,
    "cmd_name": "CMD_FRIEND_UNBLOCK_RESP",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "user_id": "user_1288"
    },
    "route_key": "",
    "seq": 4,
    "trace_id": "",
    "ts": 1785909886541,
    "ver": 1
  },
  "step": 3
}
```

</details>

---

## friend_test/拒绝好友请求
### 步骤 1：↓ WS CMD_FRIEND_ADD_RESP（A）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `801` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_FRIEND_ADD_RESP` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `2` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886567` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `request_id` | `fr997` | 好友请求 ID |
| `status` | `FRIEND_STATUS_PENDING` | ACK 状态：ACK_SERVER_RECEIVED / ACK_CLIENT_RECEIVED |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "A",
  "case": "friend_test/拒绝好友请求",
  "direction": "↓ WS CMD_FRIEND_ADD_RESP",
  "note": "↓ WS CMD_FRIEND_ADD_RESP",
  "packet": {
    "cid": "",
    "cmd": 801,
    "cmd_name": "CMD_FRIEND_ADD_RESP",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "request_id": "fr997",
      "status": "FRIEND_STATUS_PENDING"
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785909886567,
    "ver": 1
  },
  "step": 1
}
```

</details>

### 步骤 2：↓ WS CMD_FRIEND_REJECT_RESP（B）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `807` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_FRIEND_REJECT_RESP` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `2` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886571` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `friend_user_id` | `user_1446` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "B",
  "case": "friend_test/拒绝好友请求",
  "direction": "↓ WS CMD_FRIEND_REJECT_RESP",
  "note": "↓ WS CMD_FRIEND_REJECT_RESP",
  "packet": {
    "cid": "",
    "cmd": 807,
    "cmd_name": "CMD_FRIEND_REJECT_RESP",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "friend_user_id": "user_1446"
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785909886571,
    "ver": 1
  },
  "step": 2
}
```

</details>

---

## friend_test/添加-接受-列表-备注-删除
### 步骤 1：↓ WS CMD_FRIEND_ADD_RESP（A）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `801` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_FRIEND_ADD_RESP` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `2` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886505` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `request_id` | `fr6663` | 好友请求 ID |
| `status` | `FRIEND_STATUS_PENDING` | ACK 状态：ACK_SERVER_RECEIVED / ACK_CLIENT_RECEIVED |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "A",
  "case": "friend_test/添加-接受-列表-备注-删除",
  "direction": "↓ WS CMD_FRIEND_ADD_RESP",
  "note": "↓ WS CMD_FRIEND_ADD_RESP",
  "packet": {
    "cid": "",
    "cmd": 801,
    "cmd_name": "CMD_FRIEND_ADD_RESP",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "request_id": "fr6663",
      "status": "FRIEND_STATUS_PENDING"
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785909886505,
    "ver": 1
  },
  "step": 1
}
```

</details>

### 步骤 2：↓ WS CMD_FRIEND_ACCEPT_RESP（B）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `804` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_FRIEND_ACCEPT_RESP` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `2` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886508` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `friend_user_id` | `user_709` |  |
| `status` | `FRIEND_STATUS_ACCEPTED` | ACK 状态：ACK_SERVER_RECEIVED / ACK_CLIENT_RECEIVED |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "B",
  "case": "friend_test/添加-接受-列表-备注-删除",
  "direction": "↓ WS CMD_FRIEND_ACCEPT_RESP",
  "note": "↓ WS CMD_FRIEND_ACCEPT_RESP",
  "packet": {
    "cid": "",
    "cmd": 804,
    "cmd_name": "CMD_FRIEND_ACCEPT_RESP",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "friend_user_id": "user_709",
      "status": "FRIEND_STATUS_ACCEPTED"
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785909886508,
    "ver": 1
  },
  "step": 2
}
```

</details>

### 步骤 3：↓ WS CMD_FRIEND_LIST_RESP（A）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `820` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_FRIEND_LIST_RESP` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `3` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886511` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `friends` | `[{"avatar":"","created_at":1785909886504,"ext":"","nickname":"","remark":"","status":"FRIEND_STATUS_ACCEPTED","user_id":"user_1256"}]` |  |
| `has_more` | `false` |  |
| `next_cursor` | `` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "A",
  "case": "friend_test/添加-接受-列表-备注-删除",
  "direction": "↓ WS CMD_FRIEND_LIST_RESP",
  "note": "↓ WS CMD_FRIEND_LIST_RESP",
  "packet": {
    "cid": "",
    "cmd": 820,
    "cmd_name": "CMD_FRIEND_LIST_RESP",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "friends": [
        {
          "avatar": "",
          "created_at": 1785909886504,
          "ext": "",
          "nickname": "",
          "remark": "",
          "status": "FRIEND_STATUS_ACCEPTED",
          "user_id": "user_1256"
        }
      ],
      "has_more": "false",
      "next_cursor": ""
    },
    "route_key": "",
    "seq": 3,
    "trace_id": "",
    "ts": 1785909886511,
    "ver": 1
  },
  "step": 3
}
```

</details>

### 步骤 5：↑ WS CMD_FRIEND_SET_REMARK_REQ（A）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `817` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_817` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `4` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886511` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "A",
  "case": "friend_test/添加-接受-列表-备注-删除",
  "direction": "↑ WS CMD_FRIEND_SET_REMARK_REQ",
  "note": "↑ WS CMD_FRIEND_SET_REMARK_REQ",
  "packet": {
    "cid": "",
    "cmd": 817,
    "cmd_name": "CMD_817",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload_raw_bytes": 18,
    "route_key": "",
    "seq": 4,
    "trace_id": "",
    "ts": 1785909886511,
    "ver": 1
  },
  "step": 5
}
```

</details>

### 步骤 6：↓ WS CMD_FRIEND_SET_REMARK_RESP（A）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `818` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_FRIEND_SET_REMARK_RESP` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `4` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886514` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `friend_user_id` | `user_1256` |  |
| `remark` | `buddy` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "A",
  "case": "friend_test/添加-接受-列表-备注-删除",
  "direction": "↓ WS CMD_FRIEND_SET_REMARK_RESP",
  "note": "↓ WS CMD_FRIEND_SET_REMARK_RESP",
  "packet": {
    "cid": "",
    "cmd": 818,
    "cmd_name": "CMD_FRIEND_SET_REMARK_RESP",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "friend_user_id": "user_1256",
      "remark": "buddy"
    },
    "route_key": "",
    "seq": 4,
    "trace_id": "",
    "ts": 1785909886514,
    "ver": 1
  },
  "step": 6
}
```

</details>

### 步骤 7：↓ WS CMD_FRIEND_DELETE_RESP（A）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `810` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_FRIEND_DELETE_RESP` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `5` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886517` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `friend_user_id` | `user_1256` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "A",
  "case": "friend_test/添加-接受-列表-备注-删除",
  "direction": "↓ WS CMD_FRIEND_DELETE_RESP",
  "note": "↓ WS CMD_FRIEND_DELETE_RESP",
  "packet": {
    "cid": "",
    "cmd": 810,
    "cmd_name": "CMD_FRIEND_DELETE_RESP",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "friend_user_id": "user_1256"
    },
    "route_key": "",
    "seq": 5,
    "trace_id": "",
    "ts": 1785909886517,
    "ver": 1
  },
  "step": 7
}
```

</details>

---

## group_test/群生命周期与群消息
### 步骤 1：↓ WS CMD_GROUP_CREATE_RESP（owner）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `601` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_GROUP_CREATE_RESP` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `2` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909890974` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `conv_id` | `g:g-3144` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `created_at` | `1785909890974` |  |
| `group_id` | `g-3144` | 群 ID |
| `name` | `test-group` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "owner",
  "case": "group_test/群生命周期与群消息",
  "direction": "↓ WS CMD_GROUP_CREATE_RESP",
  "note": "↓ WS CMD_GROUP_CREATE_RESP",
  "packet": {
    "cid": "",
    "cmd": 601,
    "cmd_name": "CMD_GROUP_CREATE_RESP",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "conv_id": "g:g-3144",
      "created_at": 1785909890974,
      "group_id": "g-3144",
      "name": "test-group"
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785909890974,
    "ver": 1
  },
  "step": 1
}
```

</details>

### 步骤 2：↓ WS CMD_GROUP_JOIN_PUSH（extra）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `605` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_GROUP_JOIN_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `2` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909890987` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `conv_id` | `g:g-3144` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `group_id` | `g-3144` | 群 ID |
| `member_uids` | `["user_2342"]` |  |
| `operator_uid` | `user_2342` |  |
| `timestamp` | `1785909890987` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "extra",
  "case": "group_test/群生命周期与群消息",
  "direction": "↓ WS CMD_GROUP_JOIN_PUSH",
  "note": "↓ WS CMD_GROUP_JOIN_PUSH",
  "packet": {
    "cid": "",
    "cmd": 605,
    "cmd_name": "CMD_GROUP_JOIN_PUSH",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "conv_id": "g:g-3144",
      "group_id": "g-3144",
      "member_uids": [
        "user_2342"
      ],
      "operator_uid": "user_2342",
      "timestamp": 1785909890987
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785909890987,
    "ver": 1
  },
  "step": 2
}
```

</details>

### 步骤 3：↓ WS CMD_GROUP_SET_ADMIN_PUSH（owner）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `613` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_GROUP_SET_ADMIN_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `3` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909890996` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `conv_id` | `g:g-3144` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `group_id` | `g-3144` | 群 ID |
| `member_uid` | `user_2182` |  |
| `new_role` | `GROUP_MEMBER_ROLE_ADMIN` |  |
| `operator_uid` | `user_579` |  |
| `timestamp` | `1785909890994` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "owner",
  "case": "group_test/群生命周期与群消息",
  "direction": "↓ WS CMD_GROUP_SET_ADMIN_PUSH",
  "note": "↓ WS CMD_GROUP_SET_ADMIN_PUSH",
  "packet": {
    "cid": "",
    "cmd": 613,
    "cmd_name": "CMD_GROUP_SET_ADMIN_PUSH",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "conv_id": "g:g-3144",
      "group_id": "g-3144",
      "member_uid": "user_2182",
      "new_role": "GROUP_MEMBER_ROLE_ADMIN",
      "operator_uid": "user_579",
      "timestamp": 1785909890994
    },
    "route_key": "",
    "seq": 3,
    "trace_id": "",
    "ts": 1785909890996,
    "ver": 1
  },
  "step": 3
}
```

</details>

### 步骤 4：↓ WS CMD_GROUP_REMOVE_ADMIN_PUSH（owner）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `615` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_GROUP_REMOVE_ADMIN_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `4` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909890999` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `conv_id` | `g:g-3144` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `group_id` | `g-3144` | 群 ID |
| `member_uid` | `user_2182` |  |
| `new_role` | `GROUP_MEMBER_ROLE_MEMBER` |  |
| `operator_uid` | `user_579` |  |
| `timestamp` | `1785909890999` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "owner",
  "case": "group_test/群生命周期与群消息",
  "direction": "↓ WS CMD_GROUP_REMOVE_ADMIN_PUSH",
  "note": "↓ WS CMD_GROUP_REMOVE_ADMIN_PUSH",
  "packet": {
    "cid": "",
    "cmd": 615,
    "cmd_name": "CMD_GROUP_REMOVE_ADMIN_PUSH",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "conv_id": "g:g-3144",
      "group_id": "g-3144",
      "member_uid": "user_2182",
      "new_role": "GROUP_MEMBER_ROLE_MEMBER",
      "operator_uid": "user_579",
      "timestamp": 1785909890999
    },
    "route_key": "",
    "seq": 4,
    "trace_id": "",
    "ts": 1785909890999,
    "ver": 1
  },
  "step": 4
}
```

</details>

### 步骤 5：↓ WS CMD_MSG_ACK_DOWN（owner）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `201` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_ACK_DOWN` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `g-3144` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `5` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909891016` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `client_msg_id` | `68302119686465e3` | 消息级幂等 ID（业务去重） |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `msg_id` | `343273126244646912` | 服务端分配的全局消息 ID（雪花） |
| `status` | `ACK_SERVER_RECEIVED` | ACK 状态：ACK_SERVER_RECEIVED / ACK_CLIENT_RECEIVED |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "owner",
  "case": "group_test/群生命周期与群消息",
  "direction": "↓ WS CMD_MSG_ACK_DOWN",
  "note": "↓ WS CMD_MSG_ACK_DOWN",
  "packet": {
    "cid": "",
    "cmd": 201,
    "cmd_name": "CMD_MSG_ACK_DOWN",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "client_msg_id": "68302119686465e3",
      "conv_seq": 1,
      "msg_id": "343273126244646912",
      "status": "ACK_SERVER_RECEIVED"
    },
    "route_key": "g-3144",
    "seq": 5,
    "trace_id": "",
    "ts": 1785909891016,
    "ver": 1
  },
  "step": 5
}
```

</details>

### 步骤 6：↓ WS CMD_MSG_PUSH（member）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `68302119686465e3` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `101` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `g:g-3144` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `0` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909891016` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `burn_after_read` | `false` |  |
| `burn_ttl_sec` | `0` |  |
| `burned` | `false` |  |
| `chat_type` | `CHAT_GROUP` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `client_msg_id` | `68302119686465e3` | 消息级幂等 ID（业务去重） |
| `content` | `group-hi` | 消息体；MSG_TEXT 为 UTF-8 文本；MSG_STREAM 为 StreamContent 结构 |
| `conv_id` | `g:g-3144` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `edit_version` | `0` |  |
| `ext` | `{}` |  |
| `from` | `user_579` | 发送方 user_id |
| `inbox_seq` | `0` |  |
| `msg_id` | `343273126244646912` | 服务端分配的全局消息 ID（雪花） |
| `msg_type` | `MSG_TEXT` | 消息内容类型：MSG_TEXT/MSG_STREAM 等 |
| `priority` | `MSG_PRIORITY_NORMAL` |  |
| `recalled` | `false` |  |
| `server_time` | `1785909891004` | 服务端当前时间（毫秒） |
| `target_users` | `[]` |  |
| `to` | `g-3144` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "member",
  "case": "group_test/群生命周期与群消息",
  "direction": "↓ WS CMD_MSG_PUSH",
  "note": "↓ WS CMD_MSG_PUSH",
  "packet": {
    "cid": "68302119686465e3",
    "cmd": 101,
    "cmd_name": "CMD_MSG_PUSH",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "burn_after_read": "false",
      "burn_ttl_sec": 0,
      "burned": "false",
      "chat_type": "CHAT_GROUP",
      "client_msg_id": "68302119686465e3",
      "content": "group-hi",
      "conv_id": "g:g-3144",
      "conv_seq": 1,
      "edit_version": 0,
      "ext": {},
      "from": "user_579",
      "inbox_seq": 0,
      "msg_id": "343273126244646912",
      "msg_type": "MSG_TEXT",
      "priority": "MSG_PRIORITY_NORMAL",
      "recalled": "false",
      "server_time": 1785909891004,
      "target_users": [],
      "to": "g-3144"
    },
    "route_key": "g:g-3144",
    "seq": 0,
    "trace_id": "",
    "ts": 1785909891016,
    "ver": 1
  },
  "step": 6
}
```

</details>

### 步骤 7：↓ WS CMD_GROUP_LEAVE_PUSH（extra）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `607` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_GROUP_LEAVE_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `3` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909891021` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `conv_id` | `g:g-3144` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `group_id` | `g-3144` | 群 ID |
| `member_uids` | `["user_2342"]` |  |
| `operator_uid` | `user_2342` |  |
| `timestamp` | `1785909891021` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "extra",
  "case": "group_test/群生命周期与群消息",
  "direction": "↓ WS CMD_GROUP_LEAVE_PUSH",
  "note": "↓ WS CMD_GROUP_LEAVE_PUSH",
  "packet": {
    "cid": "",
    "cmd": 607,
    "cmd_name": "CMD_GROUP_LEAVE_PUSH",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "conv_id": "g:g-3144",
      "group_id": "g-3144",
      "member_uids": [
        "user_2342"
      ],
      "operator_uid": "user_2342",
      "timestamp": 1785909891021
    },
    "route_key": "",
    "seq": 3,
    "trace_id": "",
    "ts": 1785909891021,
    "ver": 1
  },
  "step": 7
}
```

</details>

### 步骤 8：↓ WS CMD_GROUP_TRANSFER_PUSH（owner）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `617` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_GROUP_TRANSFER_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `6` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909891026` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `conv_id` | `g:g-3144` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `group_id` | `g-3144` | 群 ID |
| `new_owner_uid` | `user_2182` |  |
| `old_owner_uid` | `user_579` |  |
| `timestamp` | `1785909891026` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "owner",
  "case": "group_test/群生命周期与群消息",
  "direction": "↓ WS CMD_GROUP_TRANSFER_PUSH",
  "note": "↓ WS CMD_GROUP_TRANSFER_PUSH",
  "packet": {
    "cid": "",
    "cmd": 617,
    "cmd_name": "CMD_GROUP_TRANSFER_PUSH",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "conv_id": "g:g-3144",
      "group_id": "g-3144",
      "new_owner_uid": "user_2182",
      "old_owner_uid": "user_579",
      "timestamp": 1785909891026
    },
    "route_key": "",
    "seq": 6,
    "trace_id": "",
    "ts": 1785909891026,
    "ver": 1
  },
  "step": 8
}
```

</details>

### 步骤 9：↓ WS CMD_GROUP_UPDATE_PUSH（member）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `619` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_GROUP_UPDATE_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `2` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909891029` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `announcement` | `ann` |  |
| `conv_id` | `g:g-3144` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `group_id` | `g-3144` | 群 ID |
| `name` | `renamed` |  |
| `operator_uid` | `user_2182` |  |
| `timestamp` | `1785909891029` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "member",
  "case": "group_test/群生命周期与群消息",
  "direction": "↓ WS CMD_GROUP_UPDATE_PUSH",
  "note": "↓ WS CMD_GROUP_UPDATE_PUSH",
  "packet": {
    "cid": "",
    "cmd": 619,
    "cmd_name": "CMD_GROUP_UPDATE_PUSH",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "announcement": "ann",
      "conv_id": "g:g-3144",
      "group_id": "g-3144",
      "name": "renamed",
      "operator_uid": "user_2182",
      "timestamp": 1785909891029
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785909891029,
    "ver": 1
  },
  "step": 9
}
```

</details>

### 步骤 10：↓ WS CMD_GROUP_INVITE_PUSH（member）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `611` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_GROUP_INVITE_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `3` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909891033` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `conv_id` | `g:g-3144` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `group_id` | `g-3144` | 群 ID |
| `member_uids` | `["user_2502"]` |  |
| `operator_uid` | `user_2182` |  |
| `timestamp` | `1785909891033` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "member",
  "case": "group_test/群生命周期与群消息",
  "direction": "↓ WS CMD_GROUP_INVITE_PUSH",
  "note": "↓ WS CMD_GROUP_INVITE_PUSH",
  "packet": {
    "cid": "",
    "cmd": 611,
    "cmd_name": "CMD_GROUP_INVITE_PUSH",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "conv_id": "g:g-3144",
      "group_id": "g-3144",
      "member_uids": [
        "user_2502"
      ],
      "operator_uid": "user_2182",
      "timestamp": 1785909891033
    },
    "route_key": "",
    "seq": 3,
    "trace_id": "",
    "ts": 1785909891033,
    "ver": 1
  },
  "step": 10
}
```

</details>

### 步骤 11：↓ WS CMD_GROUP_KICK_PUSH（member）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `609` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_GROUP_KICK_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `4` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909891037` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `conv_id` | `g:g-3144` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `group_id` | `g-3144` | 群 ID |
| `member_uids` | `["user_579"]` |  |
| `operator_uid` | `user_2182` |  |
| `timestamp` | `1785909891037` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "member",
  "case": "group_test/群生命周期与群消息",
  "direction": "↓ WS CMD_GROUP_KICK_PUSH",
  "note": "↓ WS CMD_GROUP_KICK_PUSH",
  "packet": {
    "cid": "",
    "cmd": 609,
    "cmd_name": "CMD_GROUP_KICK_PUSH",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "conv_id": "g:g-3144",
      "group_id": "g-3144",
      "member_uids": [
        "user_579"
      ],
      "operator_uid": "user_2182",
      "timestamp": 1785909891037
    },
    "route_key": "",
    "seq": 4,
    "trace_id": "",
    "ts": 1785909891037,
    "ver": 1
  },
  "step": 11
}
```

</details>

### 步骤 12：↓ WS CMD_GROUP_DISMISS_PUSH（member）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `603` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_GROUP_DISMISS_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `5` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909891040` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `conv_id` | `g:g-3144` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `group_id` | `g-3144` | 群 ID |
| `operator_uid` | `user_2182` |  |
| `reason` | `` | 踢下线/撤回等原因 |
| `timestamp` | `1785909891040` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "member",
  "case": "group_test/群生命周期与群消息",
  "direction": "↓ WS CMD_GROUP_DISMISS_PUSH",
  "note": "↓ WS CMD_GROUP_DISMISS_PUSH",
  "packet": {
    "cid": "",
    "cmd": 603,
    "cmd_name": "CMD_GROUP_DISMISS_PUSH",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "conv_id": "g:g-3144",
      "group_id": "g-3144",
      "operator_uid": "user_2182",
      "reason": "",
      "timestamp": 1785909891040
    },
    "route_key": "",
    "seq": 5,
    "trace_id": "",
    "ts": 1785909891040,
    "ver": 1
  },
  "step": 12
}
```

</details>

---

## offline_test/离线消息可通过 CMD_OFFLINE_PULL 拉取
### 步骤 2：↑ WS CMD_OFFLINE_PULL_REQ（B）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `300` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_OFFLINE_PULL_REQ` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `1` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886747` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `conv_id` | `p:user_1478:user_1638` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `cursor` | `0` | 离线拉取游标（conv_seq） |
| `limit` | `50` | 离线拉取条数上限 |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "B",
  "case": "offline_test/离线消息可通过 CMD_OFFLINE_PULL 拉取",
  "direction": "↑ WS CMD_OFFLINE_PULL_REQ",
  "note": "↑ WS CMD_OFFLINE_PULL_REQ",
  "packet": {
    "cid": "",
    "cmd": 300,
    "cmd_name": "CMD_OFFLINE_PULL_REQ",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "conv_id": "p:user_1478:user_1638",
      "cursor": 0,
      "limit": 50
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785909886747,
    "ver": 1
  },
  "step": 2
}
```

</details>

### 步骤 3：↓ WS CMD_OFFLINE_PULL_RESP（B）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `301` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_OFFLINE_PULL_RESP` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `2` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886750` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `has_more` | `false` |  |
| `messages` | `[{"burn_after_read":"false","burn_ttl_sec":0,"burned":"false","chat_type":"CHAT_PRIVATE","client_msg_id":"cm-1702","content":"offline-msg","conv_id":"p:user_1478:user_1638","conv_seq":1,"edit_version":0,"ext":{},"from":"user_1478","inbox_seq":2,"msg_id":"343273108343357440","msg_type":"MSG_TEXT","priority":"MSG_PRIORITY_NORMAL","recalled":"false","server_time":1785909886736,"target_users":[],"to":"user_1638"}]` |  |
| `next_cursor` | `1` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "B",
  "case": "offline_test/离线消息可通过 CMD_OFFLINE_PULL 拉取",
  "direction": "↓ WS CMD_OFFLINE_PULL_RESP",
  "note": "↓ WS CMD_OFFLINE_PULL_RESP",
  "packet": {
    "cid": "",
    "cmd": 301,
    "cmd_name": "CMD_OFFLINE_PULL_RESP",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "has_more": "false",
      "messages": [
        {
          "burn_after_read": "false",
          "burn_ttl_sec": 0,
          "burned": "false",
          "chat_type": "CHAT_PRIVATE",
          "client_msg_id": "cm-1702",
          "content": "offline-msg",
          "conv_id": "p:user_1478:user_1638",
          "conv_seq": 1,
          "edit_version": 0,
          "ext": {},
          "from": "user_1478",
          "inbox_seq": 2,
          "msg_id": "343273108343357440",
          "msg_type": "MSG_TEXT",
          "priority": "MSG_PRIORITY_NORMAL",
          "recalled": "false",
          "server_time": 1785909886736,
          "target_users": [],
          "to": "user_1638"
        }
      ],
      "next_cursor": 1
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785909886750,
    "ver": 1
  },
  "step": 3
}
```

</details>

---

## private_message_test/A 发单聊 → B 收 PUSH + 客户端 ACK
### 步骤 2：↑ WS CMD_MSG_SEND（A）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `100` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_SEND` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `1` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909891070` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `message` | `{"burn_after_read":"false","burn_ttl_sec":0,"burned":"false","chat_type":"CHAT_PRIVATE","client_msg_id":"cm-3528","content":"hi-b","conv_id":"","conv_seq":0,"edit_version":0,"ext":{},"from":"user_3240","inbox_seq":0,"msg_id":"","msg_type":"MSG_TEXT","priority":"MSG_PRIORITY_NORMAL","recalled":"false","server_time":0,"target_users":[],"to":"user_3368"}` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "A",
  "case": "private_message_test/A 发单聊 → B 收 PUSH + 客户端 ACK",
  "direction": "↑ WS CMD_MSG_SEND",
  "note": "↑ WS CMD_MSG_SEND",
  "packet": {
    "cid": "",
    "cmd": 100,
    "cmd_name": "CMD_MSG_SEND",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "message": {
        "burn_after_read": "false",
        "burn_ttl_sec": 0,
        "burned": "false",
        "chat_type": "CHAT_PRIVATE",
        "client_msg_id": "cm-3528",
        "content": "hi-b",
        "conv_id": "",
        "conv_seq": 0,
        "edit_version": 0,
        "ext": {},
        "from": "user_3240",
        "inbox_seq": 0,
        "msg_id": "",
        "msg_type": "MSG_TEXT",
        "priority": "MSG_PRIORITY_NORMAL",
        "recalled": "false",
        "server_time": 0,
        "target_users": [],
        "to": "user_3368"
      }
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785909891070,
    "ver": 1
  },
  "step": 2
}
```

</details>

### 步骤 3：↓ WS CMD_MSG_ACK_DOWN（A）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `201` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_ACK_DOWN` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `2` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909891080` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `client_msg_id` | `cm-3528` | 消息级幂等 ID（业务去重） |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `msg_id` | `343273126538248192` | 服务端分配的全局消息 ID（雪花） |
| `status` | `ACK_SERVER_RECEIVED` | ACK 状态：ACK_SERVER_RECEIVED / ACK_CLIENT_RECEIVED |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "A",
  "case": "private_message_test/A 发单聊 → B 收 PUSH + 客户端 ACK",
  "direction": "↓ WS CMD_MSG_ACK_DOWN",
  "note": "↓ WS CMD_MSG_ACK_DOWN",
  "packet": {
    "cid": "",
    "cmd": 201,
    "cmd_name": "CMD_MSG_ACK_DOWN",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "client_msg_id": "cm-3528",
      "conv_seq": 1,
      "msg_id": "343273126538248192",
      "status": "ACK_SERVER_RECEIVED"
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785909891080,
    "ver": 1
  },
  "step": 3
}
```

</details>

### 步骤 4：↓ WS CMD_MSG_PUSH（B）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `cm-3528` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `101` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `p:user_3240:user_3368` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `0` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909891080` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `burn_after_read` | `false` |  |
| `burn_ttl_sec` | `0` |  |
| `burned` | `false` |  |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `client_msg_id` | `cm-3528` | 消息级幂等 ID（业务去重） |
| `content` | `hi-b` | 消息体；MSG_TEXT 为 UTF-8 文本；MSG_STREAM 为 StreamContent 结构 |
| `conv_id` | `p:user_3240:user_3368` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `edit_version` | `0` |  |
| `ext` | `{}` |  |
| `from` | `user_3240` | 发送方 user_id |
| `inbox_seq` | `0` |  |
| `msg_id` | `343273126538248192` | 服务端分配的全局消息 ID（雪花） |
| `msg_type` | `MSG_TEXT` | 消息内容类型：MSG_TEXT/MSG_STREAM 等 |
| `priority` | `MSG_PRIORITY_NORMAL` |  |
| `recalled` | `false` |  |
| `server_time` | `1785909891074` | 服务端当前时间（毫秒） |
| `target_users` | `[]` |  |
| `to` | `user_3368` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "B",
  "case": "private_message_test/A 发单聊 → B 收 PUSH + 客户端 ACK",
  "direction": "↓ WS CMD_MSG_PUSH",
  "note": "↓ WS CMD_MSG_PUSH",
  "packet": {
    "cid": "cm-3528",
    "cmd": 101,
    "cmd_name": "CMD_MSG_PUSH",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "burn_after_read": "false",
      "burn_ttl_sec": 0,
      "burned": "false",
      "chat_type": "CHAT_PRIVATE",
      "client_msg_id": "cm-3528",
      "content": "hi-b",
      "conv_id": "p:user_3240:user_3368",
      "conv_seq": 1,
      "edit_version": 0,
      "ext": {},
      "from": "user_3240",
      "inbox_seq": 0,
      "msg_id": "343273126538248192",
      "msg_type": "MSG_TEXT",
      "priority": "MSG_PRIORITY_NORMAL",
      "recalled": "false",
      "server_time": 1785909891074,
      "target_users": [],
      "to": "user_3368"
    },
    "route_key": "p:user_3240:user_3368",
    "seq": 0,
    "trace_id": "",
    "ts": 1785909891080,
    "ver": 1
  },
  "step": 4
}
```

</details>

### 步骤 6：↑ WS CMD_MSG_ACK_UP（B）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `200` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_ACK_UP` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `5` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909891082` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `client_msg_id` | `cm-3528` | 消息级幂等 ID（业务去重） |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `msg_id` | `343273126538248192` | 服务端分配的全局消息 ID（雪花） |
| `status` | `ACK_CLIENT_RECEIVED` | ACK 状态：ACK_SERVER_RECEIVED / ACK_CLIENT_RECEIVED |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "B",
  "case": "private_message_test/A 发单聊 → B 收 PUSH + 客户端 ACK",
  "direction": "↑ WS CMD_MSG_ACK_UP",
  "note": "↑ WS CMD_MSG_ACK_UP",
  "packet": {
    "cid": "",
    "cmd": 200,
    "cmd_name": "CMD_MSG_ACK_UP",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "client_msg_id": "cm-3528",
      "conv_seq": 1,
      "msg_id": "343273126538248192",
      "status": "ACK_CLIENT_RECEIVED"
    },
    "route_key": "",
    "seq": 5,
    "trace_id": "",
    "ts": 1785909891082,
    "ver": 1
  },
  "step": 6
}
```

</details>

---

## private_message_test/REST 发消息双通道
### 步骤 1：↑ HTTP POST /api/v1/messages（A）

**HTTP 请求体**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `content` | `rest-path` | 消息体；MSG_TEXT 为 UTF-8 文本；MSG_STREAM 为 StreamContent 结构 |
| `to` | `user_2918` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |

**HTTP 响应体（节选）**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `client_msg_id` | `c0c5c00195773177` | 消息级幂等 ID（业务去重） |
| `conv_id` | `p:user_2918:user_3560` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `duplicate` | `false` |  |
| `msg_id` | `343273126634717184` | 服务端分配的全局消息 ID（雪花） |
| `server_time` | `1785909891097` | 服务端当前时间（毫秒） |
| `status` | `SERVER_RECEIVED` | ACK 状态：ACK_SERVER_RECEIVED / ACK_CLIENT_RECEIVED |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "A",
  "case": "private_message_test/REST 发消息双通道",
  "direction": "↑ HTTP POST /api/v1/messages",
  "http": {
    "request": {
      "content": "rest-path",
      "to": "user_2918"
    },
    "response": {
      "body": {
        "client_msg_id": "c0c5c00195773177",
        "conv_id": "p:user_2918:user_3560",
        "conv_seq": 1,
        "duplicate": false,
        "msg_id": "343273126634717184",
        "server_time": 1785909891097,
        "status": "SERVER_RECEIVED"
      },
      "status": 200
    }
  },
  "note": "↑ HTTP POST /api/v1/messages",
  "step": 1
}
```

</details>

### 步骤 2：↓ WS CMD_MSG_PUSH（B）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `c0c5c00195773177` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `101` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `p:user_2918:user_3560` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `0` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `lt-cc284ec4f817` | 链路追踪 ID |
| `ts` | `1785909891102` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `burn_after_read` | `false` |  |
| `burn_ttl_sec` | `0` |  |
| `burned` | `false` |  |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `client_msg_id` | `c0c5c00195773177` | 消息级幂等 ID（业务去重） |
| `content` | `rest-path` | 消息体；MSG_TEXT 为 UTF-8 文本；MSG_STREAM 为 StreamContent 结构 |
| `conv_id` | `p:user_2918:user_3560` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `edit_version` | `0` |  |
| `ext` | `{}` |  |
| `from` | `user_3560` | 发送方 user_id |
| `inbox_seq` | `0` |  |
| `msg_id` | `343273126634717184` | 服务端分配的全局消息 ID（雪花） |
| `msg_type` | `MSG_TEXT` | 消息内容类型：MSG_TEXT/MSG_STREAM 等 |
| `priority` | `MSG_PRIORITY_NORMAL` |  |
| `recalled` | `false` |  |
| `server_time` | `1785909891097` | 服务端当前时间（毫秒） |
| `target_users` | `[]` |  |
| `to` | `user_2918` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "B",
  "case": "private_message_test/REST 发消息双通道",
  "direction": "↓ WS CMD_MSG_PUSH",
  "note": "↓ WS CMD_MSG_PUSH",
  "packet": {
    "cid": "c0c5c00195773177",
    "cmd": 101,
    "cmd_name": "CMD_MSG_PUSH",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "burn_after_read": "false",
      "burn_ttl_sec": 0,
      "burned": "false",
      "chat_type": "CHAT_PRIVATE",
      "client_msg_id": "c0c5c00195773177",
      "content": "rest-path",
      "conv_id": "p:user_2918:user_3560",
      "conv_seq": 1,
      "edit_version": 0,
      "ext": {},
      "from": "user_3560",
      "inbox_seq": 0,
      "msg_id": "343273126634717184",
      "msg_type": "MSG_TEXT",
      "priority": "MSG_PRIORITY_NORMAL",
      "recalled": "false",
      "server_time": 1785909891097,
      "target_users": [],
      "to": "user_2918"
    },
    "route_key": "p:user_2918:user_3560",
    "seq": 0,
    "trace_id": "lt-cc284ec4f817",
    "ts": 1785909891102,
    "ver": 1
  },
  "step": 2
}
```

</details>

---

## private_message_test/client_msg_id 幂等
### 步骤 2：↑ WS CMD_MSG_SEND (1st)（A）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `100` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_SEND` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `1` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909891052` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `message` | `{"burn_after_read":"false","burn_ttl_sec":0,"burned":"false","chat_type":"CHAT_PRIVATE","client_msg_id":"idem-3208","content":"once","conv_id":"","conv_seq":0,"edit_version":0,"ext":{},"from":"user_9255","inbox_seq":0,"msg_id":"","msg_type":"MSG_TEXT","priority":"MSG_PRIORITY_NORMAL","recalled":"false","server_time":0,"target_users":[],"to":"user_3176"}` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "A",
  "case": "private_message_test/client_msg_id 幂等",
  "direction": "↑ WS CMD_MSG_SEND (1st)",
  "note": "↑ WS CMD_MSG_SEND (1st)",
  "packet": {
    "cid": "",
    "cmd": 100,
    "cmd_name": "CMD_MSG_SEND",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "message": {
        "burn_after_read": "false",
        "burn_ttl_sec": 0,
        "burned": "false",
        "chat_type": "CHAT_PRIVATE",
        "client_msg_id": "idem-3208",
        "content": "once",
        "conv_id": "",
        "conv_seq": 0,
        "edit_version": 0,
        "ext": {},
        "from": "user_9255",
        "inbox_seq": 0,
        "msg_id": "",
        "msg_type": "MSG_TEXT",
        "priority": "MSG_PRIORITY_NORMAL",
        "recalled": "false",
        "server_time": 0,
        "target_users": [],
        "to": "user_3176"
      }
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785909891052,
    "ver": 1
  },
  "step": 2
}
```

</details>

### 步骤 3：↓ WS CMD_MSG_ACK_DOWN (1st)（A）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `201` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_ACK_DOWN` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `2` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909891058` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `client_msg_id` | `idem-3208` | 消息级幂等 ID（业务去重） |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `msg_id` | `343273126454362112` | 服务端分配的全局消息 ID（雪花） |
| `status` | `ACK_SERVER_RECEIVED` | ACK 状态：ACK_SERVER_RECEIVED / ACK_CLIENT_RECEIVED |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "A",
  "case": "private_message_test/client_msg_id 幂等",
  "direction": "↓ WS CMD_MSG_ACK_DOWN (1st)",
  "note": "↓ WS CMD_MSG_ACK_DOWN (1st)",
  "packet": {
    "cid": "",
    "cmd": 201,
    "cmd_name": "CMD_MSG_ACK_DOWN",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "client_msg_id": "idem-3208",
      "conv_seq": 1,
      "msg_id": "343273126454362112",
      "status": "ACK_SERVER_RECEIVED"
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785909891058,
    "ver": 1
  },
  "step": 3
}
```

</details>

### 步骤 4：↓ WS CMD_MSG_ACK_DOWN (2nd 幂等)（A）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `201` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_ACK_DOWN` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `3` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909891059` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `client_msg_id` | `idem-3208` | 消息级幂等 ID（业务去重） |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `msg_id` | `343273126454362112` | 服务端分配的全局消息 ID（雪花） |
| `status` | `ACK_SERVER_RECEIVED` | ACK 状态：ACK_SERVER_RECEIVED / ACK_CLIENT_RECEIVED |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "A",
  "case": "private_message_test/client_msg_id 幂等",
  "direction": "↓ WS CMD_MSG_ACK_DOWN (2nd 幂等)",
  "note": "↓ WS CMD_MSG_ACK_DOWN (2nd 幂等)",
  "packet": {
    "cid": "",
    "cmd": 201,
    "cmd_name": "CMD_MSG_ACK_DOWN",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "client_msg_id": "idem-3208",
      "conv_seq": 1,
      "msg_id": "343273126454362112",
      "status": "ACK_SERVER_RECEIVED"
    },
    "route_key": "",
    "seq": 3,
    "trace_id": "",
    "ts": 1785909891059,
    "ver": 1
  },
  "step": 4
}
```

</details>

---

## private_message_test/批量 ACK
### 步骤 2：↑ WS CMD_MSG_ACK_BATCH_UP（B）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `203` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_ACK_BATCH_UP` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `1` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909891128` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `acks` | `[{"client_msg_id":"cm-3334","conv_seq":1,"msg_id":"343273126739574784","status":"ACK_CLIENT_RECEIVED"}]` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "B",
  "case": "private_message_test/批量 ACK",
  "direction": "↑ WS CMD_MSG_ACK_BATCH_UP",
  "note": "↑ WS CMD_MSG_ACK_BATCH_UP",
  "packet": {
    "cid": "",
    "cmd": 203,
    "cmd_name": "CMD_MSG_ACK_BATCH_UP",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "acks": [
        {
          "client_msg_id": "cm-3334",
          "conv_seq": 1,
          "msg_id": "343273126739574784",
          "status": "ACK_CLIENT_RECEIVED"
        }
      ]
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785909891128,
    "ver": 1
  },
  "step": 2
}
```

</details>

---

## room_test/聊天室生命周期与广播
### 步骤 1：↓ WS CMD_ROOM_CREATE_RESP（owner）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `701` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_ROOM_CREATE_RESP` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `2` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886448` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `conv_id` | `r:room-1192` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `created_at` | `1785909886443` |  |
| `name` | `lobby` |  |
| `room_id` | `room-1192` | 聊天室 ID |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "owner",
  "case": "room_test/聊天室生命周期与广播",
  "direction": "↓ WS CMD_ROOM_CREATE_RESP",
  "note": "↓ WS CMD_ROOM_CREATE_RESP",
  "packet": {
    "cid": "",
    "cmd": 701,
    "cmd_name": "CMD_ROOM_CREATE_RESP",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "conv_id": "r:room-1192",
      "created_at": 1785909886443,
      "name": "lobby",
      "room_id": "room-1192"
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785909886448,
    "ver": 1
  },
  "step": 1
}
```

</details>

### 步骤 2：↓ WS CMD_ROOM_JOIN_PUSH（guest）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `705` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_ROOM_JOIN_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `2` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886453` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `conv_id` | `r:room-1192` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `member_uids` | `["user_614"]` |  |
| `operator_uid` | `user_614` |  |
| `room_id` | `room-1192` | 聊天室 ID |
| `timestamp` | `1785909886452` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "guest",
  "case": "room_test/聊天室生命周期与广播",
  "direction": "↓ WS CMD_ROOM_JOIN_PUSH",
  "note": "↓ WS CMD_ROOM_JOIN_PUSH",
  "packet": {
    "cid": "",
    "cmd": 705,
    "cmd_name": "CMD_ROOM_JOIN_PUSH",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "conv_id": "r:room-1192",
      "member_uids": [
        "user_614"
      ],
      "operator_uid": "user_614",
      "room_id": "room-1192",
      "timestamp": 1785909886452
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785909886453,
    "ver": 1
  },
  "step": 2
}
```

</details>

### 步骤 4：↑ WS CMD_ROOM_UPDATE_REQ（owner）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `710` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_710` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `3` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886453` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "owner",
  "case": "room_test/聊天室生命周期与广播",
  "direction": "↑ WS CMD_ROOM_UPDATE_REQ",
  "note": "↑ WS CMD_ROOM_UPDATE_REQ",
  "packet": {
    "cid": "",
    "cmd": 710,
    "cmd_name": "CMD_710",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload_raw_bytes": 20,
    "route_key": "",
    "seq": 3,
    "trace_id": "",
    "ts": 1785909886453,
    "ver": 1
  },
  "step": 4
}
```

</details>

### 步骤 5：↓ WS CMD_ROOM_UPDATE_PUSH（owner）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `711` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_ROOM_UPDATE_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `3` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886455` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `conv_id` | `r:room-1192` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `name` | `lobby-2` |  |
| `operator_uid` | `user_454` |  |
| `room_id` | `room-1192` | 聊天室 ID |
| `timestamp` | `1785909886454` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "owner",
  "case": "room_test/聊天室生命周期与广播",
  "direction": "↓ WS CMD_ROOM_UPDATE_PUSH",
  "note": "↓ WS CMD_ROOM_UPDATE_PUSH",
  "packet": {
    "cid": "",
    "cmd": 711,
    "cmd_name": "CMD_ROOM_UPDATE_PUSH",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "conv_id": "r:room-1192",
      "name": "lobby-2",
      "operator_uid": "user_454",
      "room_id": "room-1192",
      "timestamp": 1785909886454
    },
    "route_key": "",
    "seq": 3,
    "trace_id": "",
    "ts": 1785909886455,
    "ver": 1
  },
  "step": 5
}
```

</details>

### 步骤 6：↓ WS CMD_MSG_ACK_DOWN（owner）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `201` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_ACK_DOWN` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `room-1192` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `4` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886456` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `client_msg_id` | `53e7f77ab719cfb5` | 消息级幂等 ID（业务去重） |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `msg_id` | `343273107168952320` | 服务端分配的全局消息 ID（雪花） |
| `status` | `ACK_SERVER_RECEIVED` | ACK 状态：ACK_SERVER_RECEIVED / ACK_CLIENT_RECEIVED |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "owner",
  "case": "room_test/聊天室生命周期与广播",
  "direction": "↓ WS CMD_MSG_ACK_DOWN",
  "note": "↓ WS CMD_MSG_ACK_DOWN",
  "packet": {
    "cid": "",
    "cmd": 201,
    "cmd_name": "CMD_MSG_ACK_DOWN",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "client_msg_id": "53e7f77ab719cfb5",
      "conv_seq": 1,
      "msg_id": "343273107168952320",
      "status": "ACK_SERVER_RECEIVED"
    },
    "route_key": "room-1192",
    "seq": 4,
    "trace_id": "",
    "ts": 1785909886456,
    "ver": 1
  },
  "step": 6
}
```

</details>

### 步骤 7：↓ WS CMD_MSG_PUSH（guest）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `53e7f77ab719cfb5` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `101` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `r:room-1192` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `0` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886456` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `burn_after_read` | `false` |  |
| `burn_ttl_sec` | `0` |  |
| `burned` | `false` |  |
| `chat_type` | `CHAT_ROOM` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `client_msg_id` | `53e7f77ab719cfb5` | 消息级幂等 ID（业务去重） |
| `content` | `room-msg` | 消息体；MSG_TEXT 为 UTF-8 文本；MSG_STREAM 为 StreamContent 结构 |
| `conv_id` | `r:room-1192` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `edit_version` | `0` |  |
| `ext` | `{}` |  |
| `from` | `user_454` | 发送方 user_id |
| `inbox_seq` | `0` |  |
| `msg_id` | `343273107168952320` | 服务端分配的全局消息 ID（雪花） |
| `msg_type` | `MSG_TEXT` | 消息内容类型：MSG_TEXT/MSG_STREAM 等 |
| `priority` | `MSG_PRIORITY_NORMAL` |  |
| `recalled` | `false` |  |
| `server_time` | `1785909886456` | 服务端当前时间（毫秒） |
| `target_users` | `[]` |  |
| `to` | `room-1192` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "guest",
  "case": "room_test/聊天室生命周期与广播",
  "direction": "↓ WS CMD_MSG_PUSH",
  "note": "↓ WS CMD_MSG_PUSH",
  "packet": {
    "cid": "53e7f77ab719cfb5",
    "cmd": 101,
    "cmd_name": "CMD_MSG_PUSH",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "burn_after_read": "false",
      "burn_ttl_sec": 0,
      "burned": "false",
      "chat_type": "CHAT_ROOM",
      "client_msg_id": "53e7f77ab719cfb5",
      "content": "room-msg",
      "conv_id": "r:room-1192",
      "conv_seq": 1,
      "edit_version": 0,
      "ext": {},
      "from": "user_454",
      "inbox_seq": 0,
      "msg_id": "343273107168952320",
      "msg_type": "MSG_TEXT",
      "priority": "MSG_PRIORITY_NORMAL",
      "recalled": "false",
      "server_time": 1785909886456,
      "target_users": [],
      "to": "room-1192"
    },
    "route_key": "r:room-1192",
    "seq": 0,
    "trace_id": "",
    "ts": 1785909886456,
    "ver": 1
  },
  "step": 7
}
```

</details>

### 步骤 9：↑ WS CMD_ROOM_KICK_REQ（owner）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `708` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_708` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `8` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886456` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "owner",
  "case": "room_test/聊天室生命周期与广播",
  "direction": "↑ WS CMD_ROOM_KICK_REQ",
  "note": "↑ WS CMD_ROOM_KICK_REQ",
  "packet": {
    "cid": "",
    "cmd": 708,
    "cmd_name": "CMD_708",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload_raw_bytes": 27,
    "route_key": "",
    "seq": 8,
    "trace_id": "",
    "ts": 1785909886456,
    "ver": 1
  },
  "step": 9
}
```

</details>

### 步骤 10：↓ WS CMD_ROOM_KICK_PUSH（owner）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `709` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_ROOM_KICK_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `5` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886459` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `conv_id` | `r:room-1192` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `member_uids` | `["user_614"]` |  |
| `operator_uid` | `user_454` |  |
| `room_id` | `room-1192` | 聊天室 ID |
| `timestamp` | `1785909886459` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "owner",
  "case": "room_test/聊天室生命周期与广播",
  "direction": "↓ WS CMD_ROOM_KICK_PUSH",
  "note": "↓ WS CMD_ROOM_KICK_PUSH",
  "packet": {
    "cid": "",
    "cmd": 709,
    "cmd_name": "CMD_ROOM_KICK_PUSH",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "conv_id": "r:room-1192",
      "member_uids": [
        "user_614"
      ],
      "operator_uid": "user_454",
      "room_id": "room-1192",
      "timestamp": 1785909886459
    },
    "route_key": "",
    "seq": 5,
    "trace_id": "",
    "ts": 1785909886459,
    "ver": 1
  },
  "step": 10
}
```

</details>

### 步骤 11：↓ WS CMD_ROOM_JOIN_PUSH (rejoin)（guest）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `705` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_ROOM_JOIN_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `3` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886460` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `conv_id` | `r:room-1192` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `member_uids` | `["user_614"]` |  |
| `operator_uid` | `user_614` |  |
| `room_id` | `room-1192` | 聊天室 ID |
| `timestamp` | `1785909886460` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "guest",
  "case": "room_test/聊天室生命周期与广播",
  "direction": "↓ WS CMD_ROOM_JOIN_PUSH (rejoin)",
  "note": "↓ WS CMD_ROOM_JOIN_PUSH (rejoin)",
  "packet": {
    "cid": "",
    "cmd": 705,
    "cmd_name": "CMD_ROOM_JOIN_PUSH",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "conv_id": "r:room-1192",
      "member_uids": [
        "user_614"
      ],
      "operator_uid": "user_614",
      "room_id": "room-1192",
      "timestamp": 1785909886460
    },
    "route_key": "",
    "seq": 3,
    "trace_id": "",
    "ts": 1785909886460,
    "ver": 1
  },
  "step": 11
}
```

</details>

### 步骤 12：↓ WS CMD_ROOM_LEAVE_PUSH（guest）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `707` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_ROOM_LEAVE_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `4` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886462` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `conv_id` | `r:room-1192` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `member_uids` | `["user_614"]` |  |
| `operator_uid` | `user_614` |  |
| `room_id` | `room-1192` | 聊天室 ID |
| `timestamp` | `1785909886462` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "guest",
  "case": "room_test/聊天室生命周期与广播",
  "direction": "↓ WS CMD_ROOM_LEAVE_PUSH",
  "note": "↓ WS CMD_ROOM_LEAVE_PUSH",
  "packet": {
    "cid": "",
    "cmd": 707,
    "cmd_name": "CMD_ROOM_LEAVE_PUSH",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "conv_id": "r:room-1192",
      "member_uids": [
        "user_614"
      ],
      "operator_uid": "user_614",
      "room_id": "room-1192",
      "timestamp": 1785909886462
    },
    "route_key": "",
    "seq": 4,
    "trace_id": "",
    "ts": 1785909886462,
    "ver": 1
  },
  "step": 12
}
```

</details>

### 步骤 14：↑ WS CMD_ROOM_DISMISS_REQ（owner）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `702` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_702` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `13` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886463` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "owner",
  "case": "room_test/聊天室生命周期与广播",
  "direction": "↑ WS CMD_ROOM_DISMISS_REQ",
  "note": "↑ WS CMD_ROOM_DISMISS_REQ",
  "packet": {
    "cid": "",
    "cmd": 702,
    "cmd_name": "CMD_702",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload_raw_bytes": 11,
    "route_key": "",
    "seq": 13,
    "trace_id": "",
    "ts": 1785909886463,
    "ver": 1
  },
  "step": 14
}
```

</details>

### 步骤 15：↓ WS CMD_ROOM_DISMISS_PUSH（owner）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `703` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_ROOM_DISMISS_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `6` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886466` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `conv_id` | `r:room-1192` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `operator_uid` | `user_454` |  |
| `reason` | `` | 踢下线/撤回等原因 |
| `room_id` | `room-1192` | 聊天室 ID |
| `timestamp` | `1785909886465` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "owner",
  "case": "room_test/聊天室生命周期与广播",
  "direction": "↓ WS CMD_ROOM_DISMISS_PUSH",
  "note": "↓ WS CMD_ROOM_DISMISS_PUSH",
  "packet": {
    "cid": "",
    "cmd": 703,
    "cmd_name": "CMD_ROOM_DISMISS_PUSH",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "conv_id": "r:room-1192",
      "operator_uid": "user_454",
      "reason": "",
      "room_id": "room-1192",
      "timestamp": 1785909886465
    },
    "route_key": "",
    "seq": 6,
    "trace_id": "",
    "ts": 1785909886466,
    "ver": 1
  },
  "step": 15
}
```

</details>

---

## session_test/内部 kick 在线设备收到 CMD_KICK
### 步骤 1：↑ HTTP POST /internal/v1/users/:id/kick（client）

**HTTP 请求体**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `user_id` | `user_5351` | 业务用户 ID |

**HTTP 响应体（节选）**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `status` | `200` | ACK 状态：ACK_SERVER_RECEIVED / ACK_CLIENT_RECEIVED |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "client",
  "case": "session_test/内部 kick 在线设备收到 CMD_KICK",
  "direction": "↑ HTTP POST /internal/v1/users/:id/kick",
  "http": {
    "request": {
      "user_id": "user_5351"
    },
    "response": {
      "status": 200
    }
  },
  "note": "↑ HTTP POST /internal/v1/users/:id/kick",
  "step": 1
}
```

</details>

### 步骤 2：↓ WS CMD_KICK（client）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `5` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_KICK` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `0` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `tr-1064` | 链路追踪 ID |
| `ts` | `1785909886385` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `clear_local_data` | `false` |  |
| `kicker` | `` |  |
| `reason` | `e2e` | 踢下线/撤回等原因 |
| `reason_code` | `KICK_REASON_ADMIN_KICK` | KickReason 枚举 |
| `timestamp` | `1785909886384` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "client",
  "case": "session_test/内部 kick 在线设备收到 CMD_KICK",
  "direction": "↓ WS CMD_KICK",
  "note": "↓ WS CMD_KICK",
  "packet": {
    "cid": "",
    "cmd": 5,
    "cmd_name": "CMD_KICK",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "clear_local_data": "false",
      "kicker": null,
      "reason": "e2e",
      "reason_code": "KICK_REASON_ADMIN_KICK",
      "timestamp": 1785909886384
    },
    "route_key": "",
    "seq": 0,
    "trace_id": "tr-1064",
    "ts": 1785909886385,
    "ver": 1
  },
  "step": 2
}
```

</details>

---

## session_test/同平台超限 kick_oldest 踢掉旧设备
### 步骤 2：↑ WS CMD_AUTH_REQ (新设备)（client）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `1` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_AUTH_REQ` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `1` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886397` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `app_key` | `app_demo` | 租户应用标识 |
| `compression_offered` | `[]` |  |
| `device_id` | `d2-5831` | 设备唯一标识 |
| `device_model` | `` |  |
| `device_name` | `` |  |
| `network` | `` |  |
| `os` | `` |  |
| `platform` | `ios` | 客户端平台：ios/android/web/desktop |
| `sdk_ver` | `0.1.0` | SDK 版本号 |
| `token` | `VthCNufIA1Z5mTQafF8SHtNBS9PeljP_OdwwZyWQYtY` | WS 鉴权 token（与 REST access_token 相同） |
| `user_id` | `user_5607` | 业务用户 ID |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "client",
  "case": "session_test/同平台超限 kick_oldest 踢掉旧设备",
  "direction": "↑ WS CMD_AUTH_REQ (新设备)",
  "note": "↑ WS CMD_AUTH_REQ (新设备)",
  "packet": {
    "cid": "",
    "cmd": 1,
    "cmd_name": "CMD_AUTH_REQ",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "app_key": "app_demo",
      "compression_offered": [],
      "device_id": "d2-5831",
      "device_model": "",
      "device_name": "",
      "network": "",
      "os": "",
      "platform": "ios",
      "sdk_ver": "0.1.0",
      "token": "VthCNufIA1Z5mTQafF8SHtNBS9PeljP_OdwwZyWQYtY",
      "user_id": "user_5607"
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785909886397,
    "ver": 1
  },
  "step": 2
}
```

</details>

### 步骤 3：↓ WS CMD_KICK (旧设备)（client）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `5` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_KICK` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `0` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886399` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `clear_local_data` | `false` |  |
| `kicker` | `` |  |
| `reason` | `device_limit` | 踢下线/撤回等原因 |
| `reason_code` | `KICK_REASON_DEVICE_LIMIT` | KickReason 枚举 |
| `timestamp` | `1785909886399` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "client",
  "case": "session_test/同平台超限 kick_oldest 踢掉旧设备",
  "direction": "↓ WS CMD_KICK (旧设备)",
  "note": "↓ WS CMD_KICK (旧设备)",
  "packet": {
    "cid": "",
    "cmd": 5,
    "cmd_name": "CMD_KICK",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "clear_local_data": "false",
      "kicker": null,
      "reason": "device_limit",
      "reason_code": "KICK_REASON_DEVICE_LIMIT",
      "timestamp": 1785909886399
    },
    "route_key": "",
    "seq": 0,
    "trace_id": "",
    "ts": 1785909886399,
    "ver": 1
  },
  "step": 3
}
```

</details>

---

## session_test/同平台超限 reject 鉴权失败
### 步骤 2：↑ WS CMD_AUTH_REQ (第2设备)（client）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `1` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_AUTH_REQ` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `1` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886411` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `app_key` | `app_demo` | 租户应用标识 |
| `compression_offered` | `[]` |  |
| `device_id` | `d2-1096` | 设备唯一标识 |
| `device_model` | `` |  |
| `device_name` | `` |  |
| `network` | `` |  |
| `os` | `` |  |
| `platform` | `ios` | 客户端平台：ios/android/web/desktop |
| `sdk_ver` | `0.1.0` | SDK 版本号 |
| `token` | `SizzdjcBZnK5vn2u9J8RASv_tF7vzTfC7ZTCb-F3E7M` | WS 鉴权 token（与 REST access_token 相同） |
| `user_id` | `user_422` | 业务用户 ID |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "client",
  "case": "session_test/同平台超限 reject 鉴权失败",
  "direction": "↑ WS CMD_AUTH_REQ (第2设备)",
  "note": "↑ WS CMD_AUTH_REQ (第2设备)",
  "packet": {
    "cid": "",
    "cmd": 1,
    "cmd_name": "CMD_AUTH_REQ",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "app_key": "app_demo",
      "compression_offered": [],
      "device_id": "d2-1096",
      "device_model": "",
      "device_name": "",
      "network": "",
      "os": "",
      "platform": "ios",
      "sdk_ver": "0.1.0",
      "token": "SizzdjcBZnK5vn2u9J8RASv_tF7vzTfC7ZTCb-F3E7M",
      "user_id": "user_422"
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785909886411,
    "ver": 1
  },
  "step": 2
}
```

</details>

### 步骤 3：↓ WS CMD_ERROR (设备数超限 reject)（client）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `6` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_ERROR` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `1` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909886413` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `code` | `CODE_DEVICE_LIMIT_EXCEEDED` | ErrorCode 枚举值 |
| `msg` | `device limit exceeded` | 人类可读错误说明 |
| `ref_cid` | `` |  |
| `ref_cmd` | `1` | 引发错误的原始请求 cmd |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "client",
  "case": "session_test/同平台超限 reject 鉴权失败",
  "direction": "↓ WS CMD_ERROR (设备数超限 reject)",
  "note": "↓ WS CMD_ERROR (设备数超限 reject)",
  "packet": {
    "cid": "",
    "cmd": 6,
    "cmd_name": "CMD_ERROR",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "code": "CODE_DEVICE_LIMIT_EXCEEDED",
      "msg": "device limit exceeded",
      "ref_cid": "",
      "ref_cmd": 1
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785909886413,
    "ver": 1
  },
  "step": 3
}
```

</details>

---

## stream_test/MSG_STREAM 四段推送至对端
### 步骤 1：↓ WS CMD_MSG_PUSH (STREAM_STATUS_START)（B）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `sm-747` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `101` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `p:user_555:user_8839` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `0` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909888502` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `burn_after_read` | `false` |  |
| `burn_ttl_sec` | `0` |  |
| `burned` | `false` |  |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `client_msg_id` | `sm-747` | 消息级幂等 ID（业务去重） |
| `content` | `{"chunk":"","content_type":"text/plain","metadata":{},"sequence":1,"status":"STREAM_STATUS_START","stream_id":"st-715"}` | 消息体；MSG_TEXT 为 UTF-8 文本；MSG_STREAM 为 StreamContent 结构 |
| `conv_id` | `p:user_555:user_8839` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `edit_version` | `0` |  |
| `ext` | `{}` |  |
| `from` | `user_8839` | 发送方 user_id |
| `inbox_seq` | `0` |  |
| `msg_id` | `343273115683389440` | 服务端分配的全局消息 ID（雪花） |
| `msg_type` | `MSG_STREAM` | 消息内容类型：MSG_TEXT/MSG_STREAM 等 |
| `priority` | `MSG_PRIORITY_NORMAL` |  |
| `recalled` | `false` |  |
| `server_time` | `1785909888486` | 服务端当前时间（毫秒） |
| `target_users` | `[]` |  |
| `to` | `user_555` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "B",
  "case": "stream_test/MSG_STREAM 四段推送至对端",
  "direction": "↓ WS CMD_MSG_PUSH (STREAM_STATUS_START)",
  "note": "↓ WS CMD_MSG_PUSH (STREAM_STATUS_START)",
  "packet": {
    "cid": "sm-747",
    "cmd": 101,
    "cmd_name": "CMD_MSG_PUSH",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "burn_after_read": "false",
      "burn_ttl_sec": 0,
      "burned": "false",
      "chat_type": "CHAT_PRIVATE",
      "client_msg_id": "sm-747",
      "content": {
        "chunk": "",
        "content_type": "text/plain",
        "metadata": {},
        "sequence": 1,
        "status": "STREAM_STATUS_START",
        "stream_id": "st-715"
      },
      "conv_id": "p:user_555:user_8839",
      "conv_seq": 1,
      "edit_version": 0,
      "ext": {},
      "from": "user_8839",
      "inbox_seq": 0,
      "msg_id": "343273115683389440",
      "msg_type": "MSG_STREAM",
      "priority": "MSG_PRIORITY_NORMAL",
      "recalled": "false",
      "server_time": 1785909888486,
      "target_users": [],
      "to": "user_555"
    },
    "route_key": "p:user_555:user_8839",
    "seq": 0,
    "trace_id": "",
    "ts": 1785909888502,
    "ver": 1
  },
  "step": 1
}
```

</details>

### 步骤 2：↓ WS CMD_MSG_PUSH (STREAM_STATUS_ONGOING)（B）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `sm-779` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `101` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `p:user_555:user_8839` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `0` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909888508` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `burn_after_read` | `false` |  |
| `burn_ttl_sec` | `0` |  |
| `burned` | `false` |  |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `client_msg_id` | `sm-779` | 消息级幂等 ID（业务去重） |
| `content` | `{"chunk":"Hel","content_type":"text/plain","metadata":{},"sequence":2,"status":"STREAM_STATUS_ONGOING","stream_id":"st-715"}` | 消息体；MSG_TEXT 为 UTF-8 文本；MSG_STREAM 为 StreamContent 结构 |
| `conv_id` | `p:user_555:user_8839` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `conv_seq` | `2` | 会话内单调排序位点 |
| `edit_version` | `0` |  |
| `ext` | `{}` |  |
| `from` | `user_8839` | 发送方 user_id |
| `inbox_seq` | `0` |  |
| `msg_id` | `343273115763081216` | 服务端分配的全局消息 ID（雪花） |
| `msg_type` | `MSG_STREAM` | 消息内容类型：MSG_TEXT/MSG_STREAM 等 |
| `priority` | `MSG_PRIORITY_NORMAL` |  |
| `recalled` | `false` |  |
| `server_time` | `1785909888505` | 服务端当前时间（毫秒） |
| `target_users` | `[]` |  |
| `to` | `user_555` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "B",
  "case": "stream_test/MSG_STREAM 四段推送至对端",
  "direction": "↓ WS CMD_MSG_PUSH (STREAM_STATUS_ONGOING)",
  "note": "↓ WS CMD_MSG_PUSH (STREAM_STATUS_ONGOING)",
  "packet": {
    "cid": "sm-779",
    "cmd": 101,
    "cmd_name": "CMD_MSG_PUSH",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "burn_after_read": "false",
      "burn_ttl_sec": 0,
      "burned": "false",
      "chat_type": "CHAT_PRIVATE",
      "client_msg_id": "sm-779",
      "content": {
        "chunk": "Hel",
        "content_type": "text/plain",
        "metadata": {},
        "sequence": 2,
        "status": "STREAM_STATUS_ONGOING",
        "stream_id": "st-715"
      },
      "conv_id": "p:user_555:user_8839",
      "conv_seq": 2,
      "edit_version": 0,
      "ext": {},
      "from": "user_8839",
      "inbox_seq": 0,
      "msg_id": "343273115763081216",
      "msg_type": "MSG_STREAM",
      "priority": "MSG_PRIORITY_NORMAL",
      "recalled": "false",
      "server_time": 1785909888505,
      "target_users": [],
      "to": "user_555"
    },
    "route_key": "p:user_555:user_8839",
    "seq": 0,
    "trace_id": "",
    "ts": 1785909888508,
    "ver": 1
  },
  "step": 2
}
```

</details>

### 步骤 3：↓ WS CMD_MSG_PUSH (STREAM_STATUS_ONGOING)（B）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `sm-811` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `101` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `p:user_555:user_8839` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `0` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909888513` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `burn_after_read` | `false` |  |
| `burn_ttl_sec` | `0` |  |
| `burned` | `false` |  |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `client_msg_id` | `sm-811` | 消息级幂等 ID（业务去重） |
| `content` | `{"chunk":"lo","content_type":"text/plain","metadata":{},"sequence":3,"status":"STREAM_STATUS_ONGOING","stream_id":"st-715"}` | 消息体；MSG_TEXT 为 UTF-8 文本；MSG_STREAM 为 StreamContent 结构 |
| `conv_id` | `p:user_555:user_8839` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `conv_seq` | `3` | 会话内单调排序位点 |
| `edit_version` | `0` |  |
| `ext` | `{}` |  |
| `from` | `user_8839` | 发送方 user_id |
| `inbox_seq` | `0` |  |
| `msg_id` | `343273115788247040` | 服务端分配的全局消息 ID（雪花） |
| `msg_type` | `MSG_STREAM` | 消息内容类型：MSG_TEXT/MSG_STREAM 等 |
| `priority` | `MSG_PRIORITY_NORMAL` |  |
| `recalled` | `false` |  |
| `server_time` | `1785909888510` | 服务端当前时间（毫秒） |
| `target_users` | `[]` |  |
| `to` | `user_555` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "B",
  "case": "stream_test/MSG_STREAM 四段推送至对端",
  "direction": "↓ WS CMD_MSG_PUSH (STREAM_STATUS_ONGOING)",
  "note": "↓ WS CMD_MSG_PUSH (STREAM_STATUS_ONGOING)",
  "packet": {
    "cid": "sm-811",
    "cmd": 101,
    "cmd_name": "CMD_MSG_PUSH",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "burn_after_read": "false",
      "burn_ttl_sec": 0,
      "burned": "false",
      "chat_type": "CHAT_PRIVATE",
      "client_msg_id": "sm-811",
      "content": {
        "chunk": "lo",
        "content_type": "text/plain",
        "metadata": {},
        "sequence": 3,
        "status": "STREAM_STATUS_ONGOING",
        "stream_id": "st-715"
      },
      "conv_id": "p:user_555:user_8839",
      "conv_seq": 3,
      "edit_version": 0,
      "ext": {},
      "from": "user_8839",
      "inbox_seq": 0,
      "msg_id": "343273115788247040",
      "msg_type": "MSG_STREAM",
      "priority": "MSG_PRIORITY_NORMAL",
      "recalled": "false",
      "server_time": 1785909888510,
      "target_users": [],
      "to": "user_555"
    },
    "route_key": "p:user_555:user_8839",
    "seq": 0,
    "trace_id": "",
    "ts": 1785909888513,
    "ver": 1
  },
  "step": 3
}
```

</details>

### 步骤 4：↓ WS CMD_MSG_PUSH (STREAM_STATUS_END)（B）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `sm-843` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `101` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `p:user_555:user_8839` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `0` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909888519` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `burn_after_read` | `false` |  |
| `burn_ttl_sec` | `0` |  |
| `burned` | `false` |  |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `client_msg_id` | `sm-843` | 消息级幂等 ID（业务去重） |
| `content` | `{"chunk":"","content_type":"text/plain","metadata":{},"sequence":4,"status":"STREAM_STATUS_END","stream_id":"st-715"}` | 消息体；MSG_TEXT 为 UTF-8 文本；MSG_STREAM 为 StreamContent 结构 |
| `conv_id` | `p:user_555:user_8839` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `conv_seq` | `4` | 会话内单调排序位点 |
| `edit_version` | `0` |  |
| `ext` | `{}` |  |
| `from` | `user_8839` | 发送方 user_id |
| `inbox_seq` | `0` |  |
| `msg_id` | `343273115809218560` | 服务端分配的全局消息 ID（雪花） |
| `msg_type` | `MSG_STREAM` | 消息内容类型：MSG_TEXT/MSG_STREAM 等 |
| `priority` | `MSG_PRIORITY_NORMAL` |  |
| `recalled` | `false` |  |
| `server_time` | `1785909888515` | 服务端当前时间（毫秒） |
| `target_users` | `[]` |  |
| `to` | `user_555` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "B",
  "case": "stream_test/MSG_STREAM 四段推送至对端",
  "direction": "↓ WS CMD_MSG_PUSH (STREAM_STATUS_END)",
  "note": "↓ WS CMD_MSG_PUSH (STREAM_STATUS_END)",
  "packet": {
    "cid": "sm-843",
    "cmd": 101,
    "cmd_name": "CMD_MSG_PUSH",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "burn_after_read": "false",
      "burn_ttl_sec": 0,
      "burned": "false",
      "chat_type": "CHAT_PRIVATE",
      "client_msg_id": "sm-843",
      "content": {
        "chunk": "",
        "content_type": "text/plain",
        "metadata": {},
        "sequence": 4,
        "status": "STREAM_STATUS_END",
        "stream_id": "st-715"
      },
      "conv_id": "p:user_555:user_8839",
      "conv_seq": 4,
      "edit_version": 0,
      "ext": {},
      "from": "user_8839",
      "inbox_seq": 0,
      "msg_id": "343273115809218560",
      "msg_type": "MSG_STREAM",
      "priority": "MSG_PRIORITY_NORMAL",
      "recalled": "false",
      "server_time": 1785909888515,
      "target_users": [],
      "to": "user_555"
    },
    "route_key": "p:user_555:user_8839",
    "seq": 0,
    "trace_id": "",
    "ts": 1785909888519,
    "ver": 1
  },
  "step": 4
}
```

</details>

---

## stream_test/MSG_STREAM 离线拉取
### 步骤 2：↑ WS CMD_OFFLINE_PULL_REQ（B）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `300` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_OFFLINE_PULL_REQ` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `1` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909888553` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `conv_id` | `p:user_2022:user_548` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `cursor` | `0` | 离线拉取游标（conv_seq） |
| `limit` | `20` | 离线拉取条数上限 |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "B",
  "case": "stream_test/MSG_STREAM 离线拉取",
  "direction": "↑ WS CMD_OFFLINE_PULL_REQ",
  "note": "↑ WS CMD_OFFLINE_PULL_REQ",
  "packet": {
    "cid": "",
    "cmd": 300,
    "cmd_name": "CMD_OFFLINE_PULL_REQ",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "conv_id": "p:user_2022:user_548",
      "cursor": 0,
      "limit": 20
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785909888553,
    "ver": 1
  },
  "step": 2
}
```

</details>

### 步骤 3：↓ WS CMD_OFFLINE_PULL_RESP（B）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `301` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_OFFLINE_PULL_RESP` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `2` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909888555` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `has_more` | `false` |  |
| `messages` | `[{"burn_after_read":"false","burn_ttl_sec":0,"burned":"false","chat_type":"CHAT_PRIVATE","client_msg_id":"sm-644","content":"\n\nst-off-612\u0010\u0001\u0018\u0001*\ntext/plain","conv_id":"p:user_2022:user_548","conv_seq":1,"edit_version":0,"ext":{},"from":"user_2022","inbox_seq":1,"msg_id":"343273115867938816","msg_type":"MSG_STREAM","priority":"MSG_PRIORITY_NORMAL","recalled":"false","server_time":1785909888530,"target_users":[],"to":"user_548"},{"burn_after_read":"false","burn_ttl_sec":0,"burned":"false","chat_type":"CHAT_PRIVATE","client_msg_id":"sm-2568","content":"\n\nst-off-612\u0010\u0002\u0018\u0002\"\u0003off*\ntext/plain","conv_id":"p:user_2022:user_548","conv_seq":2,"edit_version":0,"ext":{},"from":"user_2022","inbox_seq":2,"msg_id":"343273115905687552","msg_type":"MSG_STREAM","priority":"MSG_PRIORITY_NORMAL","recalled":"false","server_time":1785909888539,"target_users":[],"to":"user_548"},{"burn_after_read":"false","burn_ttl_sec":0,"burned":"false","chat_type":"CHAT_PRIVATE","client_msg_id":"sm-2600","content":"\n\nst-off-612\u0010\u0003\u0018\u0003*\ntext/plain","conv_id":"p:user_2022:user_548","conv_seq":3,"edit_version":0,"ext":{},"from":"user_2022","inbox_seq":3,"msg_id":"343273115930853376","msg_type":"MSG_STREAM","priority":"MSG_PRIORITY_NORMAL","recalled":"false","server_time":1785909888545,"target_users":[],"to":"user_548"}]` |  |
| `next_cursor` | `3` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "B",
  "case": "stream_test/MSG_STREAM 离线拉取",
  "direction": "↓ WS CMD_OFFLINE_PULL_RESP",
  "note": "↓ WS CMD_OFFLINE_PULL_RESP",
  "packet": {
    "cid": "",
    "cmd": 301,
    "cmd_name": "CMD_OFFLINE_PULL_RESP",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload": {
      "has_more": "false",
      "messages": [
        {
          "burn_after_read": "false",
          "burn_ttl_sec": 0,
          "burned": "false",
          "chat_type": "CHAT_PRIVATE",
          "client_msg_id": "sm-644",
          "content": "\n\nst-off-612\u0010\u0001\u0018\u0001*\ntext/plain",
          "conv_id": "p:user_2022:user_548",
          "conv_seq": 1,
          "edit_version": 0,
          "ext": {},
          "from": "user_2022",
          "inbox_seq": 1,
          "msg_id": "343273115867938816",
          "msg_type": "MSG_STREAM",
          "priority": "MSG_PRIORITY_NORMAL",
          "recalled": "false",
          "server_time": 1785909888530,
          "target_users": [],
          "to": "user_548"
        },
        {
          "burn_after_read": "false",
          "burn_ttl_sec": 0,
          "burned": "false",
          "chat_type": "CHAT_PRIVATE",
          "client_msg_id": "sm-2568",
          "content": "\n\nst-off-612\u0010\u0002\u0018\u0002\"\u0003off*\ntext/plain",
          "conv_id": "p:user_2022:user_548",
          "conv_seq": 2,
          "edit_version": 0,
          "ext": {},
          "from": "user_2022",
          "inbox_seq": 2,
          "msg_id": "343273115905687552",
          "msg_type": "MSG_STREAM",
          "priority": "MSG_PRIORITY_NORMAL",
          "recalled": "false",
          "server_time": 1785909888539,
          "target_users": [],
          "to": "user_548"
        },
        {
          "burn_after_read": "false",
          "burn_ttl_sec": 0,
          "burned": "false",
          "chat_type": "CHAT_PRIVATE",
          "client_msg_id": "sm-2600",
          "content": "\n\nst-off-612\u0010\u0003\u0018\u0003*\ntext/plain",
          "conv_id": "p:user_2022:user_548",
          "conv_seq": 3,
          "edit_version": 0,
          "ext": {},
          "from": "user_2022",
          "inbox_seq": 3,
          "msg_id": "343273115930853376",
          "msg_type": "MSG_STREAM",
          "priority": "MSG_PRIORITY_NORMAL",
          "recalled": "false",
          "server_time": 1785909888545,
          "target_users": [],
          "to": "user_548"
        }
      ],
      "next_cursor": 3
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785909888555,
    "ver": 1
  },
  "step": 3
}
```

</details>

---

## stream_test/流式透传 stream_start/chunk/end
### 步骤 2：↑ WS CMD_PASSTHROUGH (stream_start)（A）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `0` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_0` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `1` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909888564` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "A",
  "case": "stream_test/流式透传 stream_start/chunk/end",
  "direction": "↑ WS CMD_PASSTHROUGH (stream_start)",
  "note": "↑ WS CMD_PASSTHROUGH (stream_start)",
  "packet": {
    "cid": "",
    "cmd": 0,
    "cmd_name": "CMD_0",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload_raw_bytes": 62,
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785909888564,
    "ver": 1
  },
  "step": 2
}
```

</details>

### 步骤 3：↓ WS CMD_PASSTHROUGH (stream_start)（B）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `500` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_PASSTHROUGH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `0` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909888564` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `action` | `stream_start` | 透传 action 名 |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `conv_id` | `` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `data` | `{"stream_id":"ps-2696"}` | 透传 JSON 字符串 |
| `from` | `user_451` | 发送方 user_id |
| `persist` | `false` |  |
| `to` | `user_2664` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |
| `ttl_sec` | `0` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "B",
  "case": "stream_test/流式透传 stream_start/chunk/end",
  "direction": "↓ WS CMD_PASSTHROUGH (stream_start)",
  "note": "↓ WS CMD_PASSTHROUGH (stream_start)",
  "packet": {
    "cid": "",
    "cmd": 500,
    "cmd_name": "CMD_PASSTHROUGH",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "action": "stream_start",
      "chat_type": "CHAT_PRIVATE",
      "conv_id": "",
      "data": "{\"stream_id\":\"ps-2696\"}",
      "from": "user_451",
      "persist": "false",
      "to": "user_2664",
      "ttl_sec": 0
    },
    "route_key": "",
    "seq": 0,
    "trace_id": "",
    "ts": 1785909888564,
    "ver": 1
  },
  "step": 3
}
```

</details>

### 步骤 5：↑ WS CMD_PASSTHROUGH (stream_chunk)（A）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `0` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_0` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `4` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909888564` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "A",
  "case": "stream_test/流式透传 stream_start/chunk/end",
  "direction": "↑ WS CMD_PASSTHROUGH (stream_chunk)",
  "note": "↑ WS CMD_PASSTHROUGH (stream_chunk)",
  "packet": {
    "cid": "",
    "cmd": 0,
    "cmd_name": "CMD_0",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload_raw_bytes": 75,
    "route_key": "",
    "seq": 4,
    "trace_id": "",
    "ts": 1785909888564,
    "ver": 1
  },
  "step": 5
}
```

</details>

### 步骤 6：↓ WS CMD_PASSTHROUGH (stream_chunk)（B）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `500` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_PASSTHROUGH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `0` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909888564` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `action` | `stream_chunk` | 透传 action 名 |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `conv_id` | `` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `data` | `{"chunk":"Hi","stream_id":"ps-2696"}` | 透传 JSON 字符串 |
| `from` | `user_451` | 发送方 user_id |
| `persist` | `false` |  |
| `to` | `user_2664` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |
| `ttl_sec` | `0` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "B",
  "case": "stream_test/流式透传 stream_start/chunk/end",
  "direction": "↓ WS CMD_PASSTHROUGH (stream_chunk)",
  "note": "↓ WS CMD_PASSTHROUGH (stream_chunk)",
  "packet": {
    "cid": "",
    "cmd": 500,
    "cmd_name": "CMD_PASSTHROUGH",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "action": "stream_chunk",
      "chat_type": "CHAT_PRIVATE",
      "conv_id": "",
      "data": "{\"chunk\":\"Hi\",\"stream_id\":\"ps-2696\"}",
      "from": "user_451",
      "persist": "false",
      "to": "user_2664",
      "ttl_sec": 0
    },
    "route_key": "",
    "seq": 0,
    "trace_id": "",
    "ts": 1785909888564,
    "ver": 1
  },
  "step": 6
}
```

</details>

### 步骤 8：↑ WS CMD_PASSTHROUGH (stream_end)（A）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `0` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_0` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_UNSPECIFIED` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `7` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909888564` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "A",
  "case": "stream_test/流式透传 stream_start/chunk/end",
  "direction": "↑ WS CMD_PASSTHROUGH (stream_end)",
  "note": "↑ WS CMD_PASSTHROUGH (stream_end)",
  "packet": {
    "cid": "",
    "cmd": 0,
    "cmd_name": "CMD_0",
    "compression": "PAYLOAD_COMPRESSION_UNSPECIFIED",
    "payload_raw_bytes": 60,
    "route_key": "",
    "seq": 7,
    "trace_id": "",
    "ts": 1785909888564,
    "ver": 1
  },
  "step": 8
}
```

</details>

### 步骤 9：↓ WS CMD_PASSTHROUGH (stream_end)（B）

**Packet 信封**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `cid` | `` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `500` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_PASSTHROUGH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `0` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785909888564` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `action` | `stream_end` | 透传 action 名 |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `conv_id` | `` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `data` | `{"stream_id":"ps-2696"}` | 透传 JSON 字符串 |
| `from` | `user_451` | 发送方 user_id |
| `persist` | `false` |  |
| `to` | `user_2664` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |
| `ttl_sec` | `0` |  |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "B",
  "case": "stream_test/流式透传 stream_start/chunk/end",
  "direction": "↓ WS CMD_PASSTHROUGH (stream_end)",
  "note": "↓ WS CMD_PASSTHROUGH (stream_end)",
  "packet": {
    "cid": "",
    "cmd": 500,
    "cmd_name": "CMD_PASSTHROUGH",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "action": "stream_end",
      "chat_type": "CHAT_PRIVATE",
      "conv_id": "",
      "data": "{\"stream_id\":\"ps-2696\"}",
      "from": "user_451",
      "persist": "false",
      "to": "user_2664",
      "ttl_sec": 0
    },
    "route_key": "",
    "seq": 0,
    "trace_id": "",
    "ts": 1785909888564,
    "ver": 1
  },
  "step": 9
}
```

</details>
