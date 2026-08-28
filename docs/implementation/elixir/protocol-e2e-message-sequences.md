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
10. [auth_guard_test/鉴权超时静默关闭](#auth_guard_test/%E9%89%B4%E6%9D%83%E8%B6%85%E6%97%B6%E9%9D%99%E9%BB%98%E5%85%B3%E9%97%AD)
11. [channel_test/订阅与 publish](#channel_test/%E8%AE%A2%E9%98%85%E4%B8%8E%20publish)
12. [cluster_test/跨节点 PUSH 单聊](#cluster_test/%E8%B7%A8%E8%8A%82%E7%82%B9%20PUSH%20%E5%8D%95%E8%81%8A)
13. [cluster_test/跨节点 erpc 转发](#cluster_test/%E8%B7%A8%E8%8A%82%E7%82%B9%20erpc%20%E8%BD%AC%E5%8F%91)
14. [connection_test/GET metrics](#connection_test/GET%20metrics)
15. [connection_test/REST 登录 + WS AUTH + 心跳](#connection_test/REST%20%E7%99%BB%E5%BD%95%20+%20WS%20AUTH%20+%20%E5%BF%83%E8%B7%B3)
16. [connection_test/登出 DELETE sessions](#connection_test/%E7%99%BB%E5%87%BA%20DELETE%20sessions)
17. [conversation_test/REST 会话列表未读与已读同步](#conversation_test/REST%20%E4%BC%9A%E8%AF%9D%E5%88%97%E8%A1%A8%E6%9C%AA%E8%AF%BB%E4%B8%8E%E5%B7%B2%E8%AF%BB%E5%90%8C%E6%AD%A5)
18. [conversation_test/群聊会话列表未读](#conversation_test/%E7%BE%A4%E8%81%8A%E4%BC%9A%E8%AF%9D%E5%88%97%E8%A1%A8%E6%9C%AA%E8%AF%BB)
19. [extensions_test/已读回执](#extensions_test/%E5%B7%B2%E8%AF%BB%E5%9B%9E%E6%89%A7)
20. [extensions_test/撤回消息](#extensions_test/%E6%92%A4%E5%9B%9E%E6%B6%88%E6%81%AF)
21. [extensions_test/编辑消息](#extensions_test/%E7%BC%96%E8%BE%91%E6%B6%88%E6%81%AF)
22. [extensions_test/透传指令](#extensions_test/%E9%80%8F%E4%BC%A0%E6%8C%87%E4%BB%A4)
23. [extensions_test/阅后即焚：已读后双方收到 BURN_PUSH](#extensions_test/%E9%98%85%E5%90%8E%E5%8D%B3%E7%84%9A%EF%BC%9A%E5%B7%B2%E8%AF%BB%E5%90%8E%E5%8F%8C%E6%96%B9%E6%94%B6%E5%88%B0%20BURN_PUSH)
24. [friend_policy_test/require_friend_to_send](#friend_policy_test/require_friend_to_send)
25. [friend_test/好友请求列表](#friend_test/%E5%A5%BD%E5%8F%8B%E8%AF%B7%E6%B1%82%E5%88%97%E8%A1%A8)
26. [friend_test/拉黑与取消拉黑](#friend_test/%E6%8B%89%E9%BB%91%E4%B8%8E%E5%8F%96%E6%B6%88%E6%8B%89%E9%BB%91)
27. [friend_test/拒绝好友请求](#friend_test/%E6%8B%92%E7%BB%9D%E5%A5%BD%E5%8F%8B%E8%AF%B7%E6%B1%82)
28. [friend_test/添加-接受-列表-备注-删除](#friend_test/%E6%B7%BB%E5%8A%A0-%E6%8E%A5%E5%8F%97-%E5%88%97%E8%A1%A8-%E5%A4%87%E6%B3%A8-%E5%88%A0%E9%99%A4)
29. [group_test/群生命周期与群消息](#group_test/%E7%BE%A4%E7%94%9F%E5%91%BD%E5%91%A8%E6%9C%9F%E4%B8%8E%E7%BE%A4%E6%B6%88%E6%81%AF)
30. [offline_test/离线消息可通过 CMD_OFFLINE_PULL 拉取](#offline_test/%E7%A6%BB%E7%BA%BF%E6%B6%88%E6%81%AF%E5%8F%AF%E9%80%9A%E8%BF%87%20CMD_OFFLINE_PULL%20%E6%8B%89%E5%8F%96)
31. [private_message_test/A 发单聊 → B 收 PUSH + 客户端 ACK](#private_message_test/A%20%E5%8F%91%E5%8D%95%E8%81%8A%20%E2%86%92%20B%20%E6%94%B6%20PUSH%20+%20%E5%AE%A2%E6%88%B7%E7%AB%AF%20ACK)
32. [private_message_test/REST 发消息双通道](#private_message_test/REST%20%E5%8F%91%E6%B6%88%E6%81%AF%E5%8F%8C%E9%80%9A%E9%81%93)
33. [private_message_test/client_msg_id 幂等](#private_message_test/client_msg_id%20%E5%B9%82%E7%AD%89)
34. [private_message_test/批量 ACK](#private_message_test/%E6%89%B9%E9%87%8F%20ACK)
35. [room_test/聊天室生命周期与广播](#room_test/%E8%81%8A%E5%A4%A9%E5%AE%A4%E7%94%9F%E5%91%BD%E5%91%A8%E6%9C%9F%E4%B8%8E%E5%B9%BF%E6%92%AD)
36. [session_test/内部 kick 在线设备收到 CMD_KICK](#session_test/%E5%86%85%E9%83%A8%20kick%20%E5%9C%A8%E7%BA%BF%E8%AE%BE%E5%A4%87%E6%94%B6%E5%88%B0%20CMD_KICK)
37. [session_test/同平台超限 kick_oldest 踢掉旧设备](#session_test/%E5%90%8C%E5%B9%B3%E5%8F%B0%E8%B6%85%E9%99%90%20kick_oldest%20%E8%B8%A2%E6%8E%89%E6%97%A7%E8%AE%BE%E5%A4%87)
38. [session_test/同平台超限 reject 鉴权失败](#session_test/%E5%90%8C%E5%B9%B3%E5%8F%B0%E8%B6%85%E9%99%90%20reject%20%E9%89%B4%E6%9D%83%E5%A4%B1%E8%B4%A5)
39. [stream_test/MSG_STREAM 四段推送至对端](#stream_test/MSG_STREAM%20%E5%9B%9B%E6%AE%B5%E6%8E%A8%E9%80%81%E8%87%B3%E5%AF%B9%E7%AB%AF)
40. [stream_test/MSG_STREAM 离线拉取](#stream_test/MSG_STREAM%20%E7%A6%BB%E7%BA%BF%E6%8B%89%E5%8F%96)
41. [stream_test/流式透传 stream_start/chunk/end](#stream_test/%E6%B5%81%E5%BC%8F%E9%80%8F%E4%BC%A0%20stream_start/chunk/end)

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
| `ts` | `1785827566905` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `app_key` | `app_demo` | 租户应用标识 |
| `compression_offered` | `[]` |  |
| `device_id` | `wrong-device-5155` | 设备唯一标识 |
| `device_model` | `` |  |
| `device_name` | `` |  |
| `network` | `` |  |
| `os` | `` |  |
| `platform` | `ios` | 客户端平台：ios/android/web/desktop |
| `sdk_ver` | `0.1.0` | SDK 版本号 |
| `token` | `JR2JIS1WazRhYpsH4nExrmMOecAfbntPoCRGyLyfAQc` | WS 鉴权 token（与 REST access_token 相同） |
| `user_id` | `user_4261` | 业务用户 ID |

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
      "device_id": "wrong-device-5155",
      "device_model": "",
      "device_name": "",
      "network": "",
      "os": "",
      "platform": "ios",
      "sdk_ver": "0.1.0",
      "token": "JR2JIS1WazRhYpsH4nExrmMOecAfbntPoCRGyLyfAQc",
      "user_id": "user_4261"
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785827566905,
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
| `ts` | `1785827566910` | 发送时间戳（毫秒） |
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
    "ts": 1785827566910,
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
| `ts` | `1785827566212` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `app_key` | `app_demo` | 租户应用标识 |
| `compression_offered` | `[]` |  |
| `device_id` | `device_1700` | 设备唯一标识 |
| `device_model` | `` |  |
| `device_name` | `` |  |
| `network` | `` |  |
| `os` | `` |  |
| `platform` | `ios` | 客户端平台：ios/android/web/desktop |
| `sdk_ver` | `0.1.0` | SDK 版本号 |
| `token` | `8AjPIf4rOq29vFzuF8NH1STfrUF9GXSbMGcbhhF7jWQ` | WS 鉴权 token（与 REST access_token 相同） |
| `user_id` | `wrong-user-1732` | 业务用户 ID |

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
      "device_id": "device_1700",
      "device_model": "",
      "device_name": "",
      "network": "",
      "os": "",
      "platform": "ios",
      "sdk_ver": "0.1.0",
      "token": "8AjPIf4rOq29vFzuF8NH1STfrUF9GXSbMGcbhhF7jWQ",
      "user_id": "wrong-user-1732"
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785827566212,
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
| `ts` | `1785827566223` | 发送时间戳（毫秒） |
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
    "ts": 1785827566223,
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
| `ts` | `1785827565548` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `app_key` | `app_demo` | 租户应用标识 |
| `compression_offered` | `[]` |  |
| `device_id` | `device_898` | 设备唯一标识 |
| `device_model` | `` |  |
| `device_name` | `` |  |
| `network` | `` |  |
| `os` | `` |  |
| `platform` | `ios` | 客户端平台：ios/android/web/desktop |
| `sdk_ver` | `0.1.0` | SDK 版本号 |
| `token` | `LO7uwNPVRnWlu4gtEAkOoAsJxAXjfS7qbkE_TofPmAk` | WS 鉴权 token（与 REST access_token 相同） |
| `user_id` | `user_4867` | 业务用户 ID |

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
      "device_id": "device_898",
      "device_model": "",
      "device_name": "",
      "network": "",
      "os": "",
      "platform": "ios",
      "sdk_ver": "0.1.0",
      "token": "LO7uwNPVRnWlu4gtEAkOoAsJxAXjfS7qbkE_TofPmAk",
      "user_id": "user_4867"
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785827565548,
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
| `ts` | `1785827565550` | 发送时间戳（毫秒） |
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
    "ts": 1785827565550,
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
| `ts` | `1785827566190` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `app_key` | `app_demo` | 租户应用标识 |
| `compression_offered` | `[]` |  |
| `device_id` | `device_1636` | 设备唯一标识 |
| `device_model` | `` |  |
| `device_name` | `` |  |
| `network` | `` |  |
| `os` | `` |  |
| `platform` | `ios` | 客户端平台：ios/android/web/desktop |
| `sdk_ver` | `0.1.0` | SDK 版本号 |
| `token` | `bUjxB0hu23fcWZ6fmKHal5JiZ6nWg64tvJ5pQc1UV8s` | WS 鉴权 token（与 REST access_token 相同） |
| `user_id` | `user_1604` | 业务用户 ID |

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
      "device_id": "device_1636",
      "device_model": "",
      "device_name": "",
      "network": "",
      "os": "",
      "platform": "ios",
      "sdk_ver": "0.1.0",
      "token": "bUjxB0hu23fcWZ6fmKHal5JiZ6nWg64tvJ5pQc1UV8s",
      "user_id": "user_1604"
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785827566190,
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
| `ts` | `1785827566193` | 发送时间戳（毫秒） |
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
    "ts": 1785827566193,
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
| `ts` | `1785827566248` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `app_key` | `app_demo` | 租户应用标识 |
| `compression_offered` | `[]` |  |
| `device_id` | `device_4931` | 设备唯一标识 |
| `device_model` | `` |  |
| `device_name` | `` |  |
| `network` | `` |  |
| `os` | `` |  |
| `platform` | `ios` | 客户端平台：ios/android/web/desktop |
| `sdk_ver` | `1.0.0` | SDK 版本号 |
| `token` | `TSfaUJaKFcEjzS12gaUnGRrOcUMao3VPnLGZD3PPEZI` | WS 鉴权 token（与 REST access_token 相同） |
| `user_id` | `user_4899` | 业务用户 ID |

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
      "device_id": "device_4931",
      "device_model": "",
      "device_name": "",
      "network": "",
      "os": "",
      "platform": "ios",
      "sdk_ver": "1.0.0",
      "token": "TSfaUJaKFcEjzS12gaUnGRrOcUMao3VPnLGZD3PPEZI",
      "user_id": "user_4899"
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785827566248,
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
| `ts` | `1785827566249` | 发送时间戳（毫秒） |
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
    "ts": 1785827566249,
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
| `ts` | `1785827565554` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `app_key` | `app_demo` | 租户应用标识 |
| `compression_offered` | `[]` |  |
| `device_id` | `d-1572` | 设备唯一标识 |
| `device_model` | `` |  |
| `device_name` | `` |  |
| `network` | `` |  |
| `os` | `` |  |
| `platform` | `ios` | 客户端平台：ios/android/web/desktop |
| `sdk_ver` | `0.1.0` | SDK 版本号 |
| `token` | `not-a-valid-token` | WS 鉴权 token（与 REST access_token 相同） |
| `user_id` | `user_4133` | 业务用户 ID |

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
      "device_id": "d-1572",
      "device_model": "",
      "device_name": "",
      "network": "",
      "os": "",
      "platform": "ios",
      "sdk_ver": "0.1.0",
      "token": "not-a-valid-token",
      "user_id": "user_4133"
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785827565554,
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
| `ts` | `1785827565557` | 发送时间戳（毫秒） |
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
    "ts": 1785827565557,
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
| `ts` | `1785827565862` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `message` | `{"burn_after_read":"false","burn_ttl_sec":0,"burned":"false","chat_type":"CHAT_PRIVATE","client_msg_id":"cm-930","content":"illegal","conv_id":"","conv_seq":0,"edit_version":0,"ext":{},"from":"u1","inbox_seq":0,"msg_id":"","msg_type":"MSG_TEXT","priority":"MSG_PRIORITY_NORMAL","recalled":"false","server_time":0,"target_users":[],"to":"u2"}` |  |

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
        "client_msg_id": "cm-930",
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
    "ts": 1785827565862,
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
| `ts` | `1785827565559` | 发送时间戳（毫秒） |
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
    "ts": 1785827565559,
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
| `ts` | `1785827566876` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `app_key` | `app_demo` | 租户应用标识 |
| `compression_offered` | `[]` |  |
| `device_id` | `device_5091` | 设备唯一标识 |
| `device_model` | `` |  |
| `device_name` | `` |  |
| `network` | `` |  |
| `os` | `` |  |
| `platform` | `ios` | 客户端平台：ios/android/web/desktop |
| `sdk_ver` | `0.1.0` | SDK 版本号 |
| `token` | `5NiEWURJnAN-7hmfu6yERET4uUzUr3YCa--Q1S89lLM` | WS 鉴权 token（与 REST access_token 相同） |
| `user_id` | `user_5059` | 业务用户 ID |

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
      "device_id": "device_5091",
      "device_model": "",
      "device_name": "",
      "network": "",
      "os": "",
      "platform": "ios",
      "sdk_ver": "0.1.0",
      "token": "5NiEWURJnAN-7hmfu6yERET4uUzUr3YCa--Q1S89lLM",
      "user_id": "user_5059"
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785827566876,
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
| `ts` | `1785827566882` | 发送时间戳（毫秒） |
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
    "ts": 1785827566882,
    "ver": 1
  },
  "step": 3
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
| `ts` | `1785827565139` | 发送时间戳（毫秒） |
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
    "ts": 1785827565139,
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
| `trace_id` | `tr-514` | 链路追踪 ID |
| `ts` | `1785827565159` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `caller_service` | `protocol-e2e` |  |
| `channel_id` | `news:alerts` | 应用通道 ID（namespace:name） |
| `content_type` | `application/json` |  |
| `event_id` | `87821fab-678a-42a3-b9eb-f6681e18c884` |  |
| `payload` | `{"n":1}` |  |
| `server_time` | `1785827565158` | 服务端当前时间（毫秒） |

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
      "event_id": "87821fab-678a-42a3-b9eb-f6681e18c884",
      "payload": "{\"n\":1}",
      "server_time": 1785827565158
    },
    "route_key": "news:alerts",
    "seq": 0,
    "trace_id": "tr-514",
    "ts": 1785827565159,
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
| `ts` | `1785827565161` | 发送时间戳（毫秒） |
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
    "ts": 1785827565161,
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
| `ts` | `1785827565162` | 发送时间戳（毫秒） |
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
    "ts": 1785827565162,
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
| `ts` | `1785827565163` | 发送时间戳（毫秒） |
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
    "ts": 1785827565163,
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
| `ts` | `1785827565164` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `accepted` | `true` |  |
| `channel_id` | `news:alerts` | 应用通道 ID（namespace:name） |
| `event_id` | `10b60306-1733-41b6-bc01-638d8e178b2c` |  |

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
      "event_id": "10b60306-1733-41b6-bc01-638d8e178b2c"
    },
    "route_key": "",
    "seq": 4,
    "trace_id": "",
    "ts": 1785827565164,
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
| `cid` | `cm-4357` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `101` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `p:user_1924:user_4325` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `0` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785827567912` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `burn_after_read` | `false` |  |
| `burn_ttl_sec` | `0` |  |
| `burned` | `false` |  |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `client_msg_id` | `cm-4357` | 消息级幂等 ID（业务去重） |
| `content` | `cross-node-push` | 消息体；MSG_TEXT 为 UTF-8 文本；MSG_STREAM 为 StreamContent 结构 |
| `conv_id` | `p:user_1924:user_4325` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `edit_version` | `0` |  |
| `ext` | `{}` |  |
| `from` | `user_4325` | 发送方 user_id |
| `inbox_seq` | `0` |  |
| `msg_id` | `342927838057332736` | 服务端分配的全局消息 ID（雪花） |
| `msg_type` | `MSG_TEXT` | 消息内容类型：MSG_TEXT/MSG_STREAM 等 |
| `priority` | `MSG_PRIORITY_NORMAL` |  |
| `recalled` | `false` |  |
| `server_time` | `1785827567887` | 服务端当前时间（毫秒） |
| `target_users` | `[]` |  |
| `to` | `user_1924` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "B",
  "case": "cluster_test/跨节点 PUSH 单聊",
  "direction": "↓ WS CMD_MSG_PUSH (peer 节点)",
  "note": "↓ WS CMD_MSG_PUSH (peer 节点)",
  "packet": {
    "cid": "cm-4357",
    "cmd": 101,
    "cmd_name": "CMD_MSG_PUSH",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "burn_after_read": "false",
      "burn_ttl_sec": 0,
      "burned": "false",
      "chat_type": "CHAT_PRIVATE",
      "client_msg_id": "cm-4357",
      "content": "cross-node-push",
      "conv_id": "p:user_1924:user_4325",
      "conv_seq": 1,
      "edit_version": 0,
      "ext": {},
      "from": "user_4325",
      "inbox_seq": 0,
      "msg_id": "342927838057332736",
      "msg_type": "MSG_TEXT",
      "priority": "MSG_PRIORITY_NORMAL",
      "recalled": "false",
      "server_time": 1785827567887,
      "target_users": [],
      "to": "user_1924"
    },
    "route_key": "p:user_1924:user_4325",
    "seq": 0,
    "trace_id": "",
    "ts": 1785827567912,
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
| `ts` | `1785827569015` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `client_msg_id` | `cm-1378` | 消息级幂等 ID（业务去重） |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `msg_id` | `342927842662678528` | 服务端分配的全局消息 ID（雪花） |
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
      "client_msg_id": "cm-1378",
      "conv_seq": 1,
      "msg_id": "342927842662678528",
      "status": "ACK_SERVER_RECEIVED"
    },
    "route_key": "cluster-rk-1",
    "seq": 2,
    "trace_id": "",
    "ts": 1785827569015,
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
| `cid` | `cm-1378` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `101` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `p:user_4389:user_5219` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `0` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785827569015` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `burn_after_read` | `false` |  |
| `burn_ttl_sec` | `0` |  |
| `burned` | `false` |  |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `client_msg_id` | `cm-1378` | 消息级幂等 ID（业务去重） |
| `content` | `cross-node-erpc` | 消息体；MSG_TEXT 为 UTF-8 文本；MSG_STREAM 为 StreamContent 结构 |
| `conv_id` | `p:user_4389:user_5219` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `edit_version` | `0` |  |
| `ext` | `{}` |  |
| `from` | `user_5219` | 发送方 user_id |
| `inbox_seq` | `0` |  |
| `msg_id` | `342927842662678528` | 服务端分配的全局消息 ID（雪花） |
| `msg_type` | `MSG_TEXT` | 消息内容类型：MSG_TEXT/MSG_STREAM 等 |
| `priority` | `MSG_PRIORITY_NORMAL` |  |
| `recalled` | `false` |  |
| `server_time` | `1785827568986` | 服务端当前时间（毫秒） |
| `target_users` | `[]` |  |
| `to` | `user_4389` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "B",
  "case": "cluster_test/跨节点 erpc 转发",
  "direction": "↓ WS CMD_MSG_PUSH (peer)",
  "note": "↓ WS CMD_MSG_PUSH (peer)",
  "packet": {
    "cid": "cm-1378",
    "cmd": 101,
    "cmd_name": "CMD_MSG_PUSH",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "burn_after_read": "false",
      "burn_ttl_sec": 0,
      "burned": "false",
      "chat_type": "CHAT_PRIVATE",
      "client_msg_id": "cm-1378",
      "content": "cross-node-erpc",
      "conv_id": "p:user_4389:user_5219",
      "conv_seq": 1,
      "edit_version": 0,
      "ext": {},
      "from": "user_5219",
      "inbox_seq": 0,
      "msg_id": "342927842662678528",
      "msg_type": "MSG_TEXT",
      "priority": "MSG_PRIORITY_NORMAL",
      "recalled": "false",
      "server_time": 1785827568986,
      "target_users": [],
      "to": "user_4389"
    },
    "route_key": "p:user_4389:user_5219",
    "seq": 0,
    "trace_id": "",
    "ts": 1785827569015,
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
      "body": "# HELP im_permission_check_count \n# TYPE im_permission_check_count counter\nim_permission_check_count{layer=\"pg\",result=\"allow\",type=\"device_ban\"} 15\nim_permission_check_count{layer=\"l1\",result=\"allow\"…",
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
| `device_id` | `d-3877` | 设备唯一标识 |
| `user_id` | `user_3845` | 业务用户 ID |

**HTTP 响应体（节选）**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `access_token` | `hvvDwznLh5WA4-hpYRE6dB4B8_LuJcpPSYnLHJ4dCgM` | REST 返回的会话 token |
| `clear_local_data` | `false` |  |
| `config` | `{"burn_after_read_enabled":true,"burn_ttl_sec_default":0,"burn_ttl_sec_max":3600,"edit_window_sec":86400,"heartbeat_interval_sec":30,"offline_pull_limit":200,"payload_compression":"none","push_batch_max":50,"recall_window_sec":120}` |  |
| `connection` | `{"preferred_index":0,"websocket_urls":["ws://127.0.0.1:4002/ws"]}` |  |
| `expires_at` | `1785913965443` | token 过期时间（毫秒时间戳） |
| `user_id` | `user_3845` | 业务用户 ID |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "client",
  "case": "connection_test/REST 登录 + WS AUTH + 心跳",
  "direction": "↑ HTTP POST /api/v1/sessions",
  "http": {
    "request": {
      "app_key": "app_demo",
      "device_id": "d-3877",
      "user_id": "user_3845"
    },
    "response": {
      "body": {
        "access_token": "hvvDwznLh5WA4-hpYRE6dB4B8_LuJcpPSYnLHJ4dCgM",
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
        "expires_at": 1785913965443,
        "user_id": "user_3845"
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
| `ts` | `1785827565448` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `app_key` | `app_demo` | 租户应用标识 |
| `compression_offered` | `[]` |  |
| `device_id` | `d-3877` | 设备唯一标识 |
| `device_model` | `` |  |
| `device_name` | `` |  |
| `network` | `` |  |
| `os` | `` |  |
| `platform` | `ios` | 客户端平台：ios/android/web/desktop |
| `sdk_ver` | `0.1.0` | SDK 版本号 |
| `token` | `hvvDwznLh5WA4-hpYRE6dB4B8_LuJcpPSYnLHJ4dCgM` | WS 鉴权 token（与 REST access_token 相同） |
| `user_id` | `user_3845` | 业务用户 ID |

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
      "device_id": "d-3877",
      "device_model": "",
      "device_name": "",
      "network": "",
      "os": "",
      "platform": "ios",
      "sdk_ver": "0.1.0",
      "token": "hvvDwznLh5WA4-hpYRE6dB4B8_LuJcpPSYnLHJ4dCgM",
      "user_id": "user_3845"
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785827565448,
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
| `ts` | `1785827565468` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `burn_after_read_enabled` | `true` |  |
| `burn_ttl_sec_default` | `0` |  |
| `burn_ttl_sec_max` | `3600` |  |
| `clear_local_data` | `false` |  |
| `device` | `{"client_ip":"","connected_at":1785827565464,"device_id":"d-3877","device_model":"","device_name":"","network":"","os":"","platform":"loadtest","sdk_ver":"0.1.0","session_id":"b5f30d8c-aaef-4d8b-aa5f-809ab8413c96"}` |  |
| `edit_window_sec` | `86400` |  |
| `heartbeat_interval_sec` | `30` | 心跳间隔（秒） |
| `offline_pull_limit` | `200` |  |
| `payload_compression` | `PAYLOAD_COMPRESSION_NONE` |  |
| `push_batch_max` | `50` |  |
| `recall_window_sec` | `120` |  |
| `server_time` | `1785827565464` | 服务端当前时间（毫秒） |
| `user_id` | `user_3845` | 业务用户 ID |

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
        "connected_at": 1785827565464,
        "device_id": "d-3877",
        "device_model": "",
        "device_name": "",
        "network": "",
        "os": "",
        "platform": "loadtest",
        "sdk_ver": "0.1.0",
        "session_id": "b5f30d8c-aaef-4d8b-aa5f-809ab8413c96"
      },
      "edit_window_sec": 86400,
      "heartbeat_interval_sec": 30,
      "offline_pull_limit": 200,
      "payload_compression": "PAYLOAD_COMPRESSION_NONE",
      "push_batch_max": 50,
      "recall_window_sec": 120,
      "server_time": 1785827565464,
      "user_id": "user_3845"
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785827565468,
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
| `ts` | `1785827565478` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `client_time` | `1785827565478` | 客户端本地时间（毫秒） |

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
      "client_time": 1785827565478
    },
    "route_key": "",
    "seq": 5,
    "trace_id": "",
    "ts": 1785827565478,
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
| `ts` | `1785827565477` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `server_time` | `1785827565474` | 服务端当前时间（毫秒） |

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
      "server_time": 1785827565474
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785827565477,
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
| `user_id` | `user_4707` | 业务用户 ID |

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
      "user_id": "user_4707"
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
| `ts` | `1785827569492` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `message` | `{"burn_after_read":"false","burn_ttl_sec":0,"burned":"false","chat_type":"CHAT_PRIVATE","client_msg_id":"conv-5189","content":"list-preview","conv_id":"","conv_seq":0,"edit_version":0,"ext":{},"from":"user_2948","inbox_seq":0,"msg_id":"","msg_type":"MSG_TEXT","priority":"MSG_PRIORITY_NORMAL","recalled":"false","server_time":0,"target_users":[],"to":"user_5029"}` |  |

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
        "client_msg_id": "conv-5189",
        "content": "list-preview",
        "conv_id": "",
        "conv_seq": 0,
        "edit_version": 0,
        "ext": {},
        "from": "user_2948",
        "inbox_seq": 0,
        "msg_id": "",
        "msg_type": "MSG_TEXT",
        "priority": "MSG_PRIORITY_NORMAL",
        "recalled": "false",
        "server_time": 0,
        "target_users": [],
        "to": "user_5029"
      }
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785827569492,
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
| `ts` | `1785827569502` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `client_msg_id` | `conv-5189` | 消息级幂等 ID（业务去重） |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `msg_id` | `342927844810162176` | 服务端分配的全局消息 ID（雪花） |
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
      "client_msg_id": "conv-5189",
      "conv_seq": 1,
      "msg_id": "342927844810162176",
      "status": "ACK_SERVER_RECEIVED"
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785827569502,
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
| `cid` | `conv-5189` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `101` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `p:user_2948:user_5029` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `0` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785827569502` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `burn_after_read` | `false` |  |
| `burn_ttl_sec` | `0` |  |
| `burned` | `false` |  |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `client_msg_id` | `conv-5189` | 消息级幂等 ID（业务去重） |
| `content` | `list-preview` | 消息体；MSG_TEXT 为 UTF-8 文本；MSG_STREAM 为 StreamContent 结构 |
| `conv_id` | `p:user_2948:user_5029` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `edit_version` | `0` |  |
| `ext` | `{}` |  |
| `from` | `user_2948` | 发送方 user_id |
| `inbox_seq` | `0` |  |
| `msg_id` | `342927844810162176` | 服务端分配的全局消息 ID（雪花） |
| `msg_type` | `MSG_TEXT` | 消息内容类型：MSG_TEXT/MSG_STREAM 等 |
| `priority` | `MSG_PRIORITY_NORMAL` |  |
| `recalled` | `false` |  |
| `server_time` | `1785827569495` | 服务端当前时间（毫秒） |
| `target_users` | `[]` |  |
| `to` | `user_5029` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "B",
  "case": "conversation_test/REST 会话列表未读与已读同步",
  "direction": "↓ WS CMD_MSG_PUSH",
  "note": "↓ WS CMD_MSG_PUSH",
  "packet": {
    "cid": "conv-5189",
    "cmd": 101,
    "cmd_name": "CMD_MSG_PUSH",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "burn_after_read": "false",
      "burn_ttl_sec": 0,
      "burned": "false",
      "chat_type": "CHAT_PRIVATE",
      "client_msg_id": "conv-5189",
      "content": "list-preview",
      "conv_id": "p:user_2948:user_5029",
      "conv_seq": 1,
      "edit_version": 0,
      "ext": {},
      "from": "user_2948",
      "inbox_seq": 0,
      "msg_id": "342927844810162176",
      "msg_type": "MSG_TEXT",
      "priority": "MSG_PRIORITY_NORMAL",
      "recalled": "false",
      "server_time": 1785827569495,
      "target_users": [],
      "to": "user_5029"
    },
    "route_key": "p:user_2948:user_5029",
    "seq": 0,
    "trace_id": "",
    "ts": 1785827569502,
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
| `conversations` | `[{"chat_type":1,"conv_id":"p:user_2948:user_5029","last_msg_id":"342927844810162176","last_msg_preview":"list-preview","last_msg_seq":1,"last_msg_time":1785827569495,"last_msg_type":1,"last_read_conv_seq":0,"peer_id":"user_2948","unread_count":1}]` |  |
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
            "conv_id": "p:user_2948:user_5029",
            "last_msg_id": "342927844810162176",
            "last_msg_preview": "list-preview",
            "last_msg_seq": 1,
            "last_msg_time": 1785827569495,
            "last_msg_type": 1,
            "last_read_conv_seq": 0,
            "peer_id": "user_2948",
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
| `ts` | `1785827569505` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `conv_id` | `p:user_2948:user_5029` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `from` | `user_5029` | 发送方 user_id |
| `msg_id` | `342927844810162176` | 服务端分配的全局消息 ID（雪花） |
| `timestamp` | `0` |  |
| `to` | `user_2948` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |
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
      "conv_id": "p:user_2948:user_5029",
      "conv_seq": 1,
      "from": "user_5029",
      "msg_id": "342927844810162176",
      "timestamp": 0,
      "to": "user_2948",
      "unread_count": null
    },
    "route_key": "",
    "seq": 6,
    "trace_id": "",
    "ts": 1785827569505,
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
| `route_key` | `p:user_2948:user_5029` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `0` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785827569507` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `conv_id` | `p:user_2948:user_5029` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `from` | `user_5029` | 发送方 user_id |
| `msg_id` | `342927844810162176` | 服务端分配的全局消息 ID（雪花） |
| `timestamp` | `1785827569506` |  |
| `to` | `user_2948` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |
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
      "conv_id": "p:user_2948:user_5029",
      "conv_seq": 1,
      "from": "user_5029",
      "msg_id": "342927844810162176",
      "timestamp": 1785827569506,
      "to": "user_2948",
      "unread_count": 0
    },
    "route_key": "p:user_2948:user_5029",
    "seq": 0,
    "trace_id": "",
    "ts": 1785827569507,
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
| `conversations` | `[{"chat_type":1,"conv_id":"p:user_2948:user_5029","last_msg_id":"342927844810162176","last_msg_preview":"list-preview","last_msg_seq":1,"last_msg_time":1785827569495,"last_msg_type":1,"last_read_conv_seq":1,"peer_id":"user_2948","unread_count":0}]` |  |
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
            "conv_id": "p:user_2948:user_5029",
            "last_msg_id": "342927844810162176",
            "last_msg_preview": "list-preview",
            "last_msg_seq": 1,
            "last_msg_time": 1785827569495,
            "last_msg_type": 1,
            "last_read_conv_seq": 1,
            "peer_id": "user_2948",
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
| `ts` | `1785827569529` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `conv_id` | `g:gc-6723` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `created_at` | `1785827569527` |  |
| `group_id` | `gc-6723` | 群 ID |
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
      "conv_id": "g:gc-6723",
      "created_at": 1785827569527,
      "group_id": "gc-6723",
      "name": "conv-g"
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785827569529,
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
| `ts` | `1785827569535` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `client_msg_id` | `gcm-5317` | 消息级幂等 ID（业务去重） |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `msg_id` | `342927844965351424` | 服务端分配的全局消息 ID（雪花） |
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
      "client_msg_id": "gcm-5317",
      "conv_seq": 1,
      "msg_id": "342927844965351424",
      "status": "ACK_SERVER_RECEIVED"
    },
    "route_key": "",
    "seq": 3,
    "trace_id": "",
    "ts": 1785827569535,
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
| `conversations` | `[{"chat_type":2,"conv_id":"g:gc-6723","last_msg_id":"342927844965351424","last_msg_preview":"group-unread","last_msg_seq":1,"last_msg_time":1785827569531,"last_msg_type":1,"last_read_conv_seq":0,"peer_id":"gc-6723","unread_count":1}]` |  |
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
            "conv_id": "g:gc-6723",
            "last_msg_id": "342927844965351424",
            "last_msg_preview": "group-unread",
            "last_msg_seq": 1,
            "last_msg_time": 1785827569531,
            "last_msg_type": 1,
            "last_read_conv_seq": 0,
            "peer_id": "gc-6723",
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
| `ts` | `1785827569403` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `conv_id` | `p:user_1319:user_968` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `from` | `user_968` | 发送方 user_id |
| `msg_id` | `342927844399120384` | 服务端分配的全局消息 ID（雪花） |
| `timestamp` | `0` |  |
| `to` | `user_1319` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |
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
      "conv_id": "p:user_1319:user_968",
      "conv_seq": 1,
      "from": "user_968",
      "msg_id": "342927844399120384",
      "timestamp": 0,
      "to": "user_1319",
      "unread_count": null
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785827569403,
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
| `route_key` | `p:user_1319:user_968` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `0` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785827569405` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `conv_id` | `p:user_1319:user_968` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `from` | `user_968` | 发送方 user_id |
| `msg_id` | `342927844399120384` | 服务端分配的全局消息 ID（雪花） |
| `timestamp` | `1785827569405` |  |
| `to` | `user_1319` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |
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
      "conv_id": "p:user_1319:user_968",
      "conv_seq": 1,
      "from": "user_968",
      "msg_id": "342927844399120384",
      "timestamp": 1785827569405,
      "to": "user_1319",
      "unread_count": 0
    },
    "route_key": "p:user_1319:user_968",
    "seq": 0,
    "trace_id": "",
    "ts": 1785827569405,
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
| `ts` | `1785827569479` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `conv_id` | `p:user_4805:user_6307` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `from` | `user_4805` | 发送方 user_id |
| `msg_id` | `342927844701110272` | 服务端分配的全局消息 ID（雪花） |
| `reason` | `mistake` | 踢下线/撤回等原因 |
| `timestamp` | `1785827569479` |  |
| `to` | `user_6307` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |

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
      "conv_id": "p:user_4805:user_6307",
      "from": "user_4805",
      "msg_id": "342927844701110272",
      "reason": "mistake",
      "timestamp": 1785827569479,
      "to": "user_6307"
    },
    "route_key": "",
    "seq": 3,
    "trace_id": "",
    "ts": 1785827569479,
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
| `route_key` | `p:user_4805:user_6307` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `0` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785827569479` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `conv_id` | `p:user_4805:user_6307` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `from` | `user_4805` | 发送方 user_id |
| `msg_id` | `342927844701110272` | 服务端分配的全局消息 ID（雪花） |
| `reason` | `mistake` | 踢下线/撤回等原因 |
| `timestamp` | `1785827569479` |  |
| `to` | `user_6307` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |

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
      "conv_id": "p:user_4805:user_6307",
      "from": "user_4805",
      "msg_id": "342927844701110272",
      "reason": "mistake",
      "timestamp": 1785827569479,
      "to": "user_6307"
    },
    "route_key": "p:user_4805:user_6307",
    "seq": 0,
    "trace_id": "",
    "ts": 1785827569479,
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
| `ts` | `1785827569427` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `content` | `edited` | 消息体；MSG_TEXT 为 UTF-8 文本；MSG_STREAM 为 StreamContent 结构 |
| `conv_id` | `p:user_5507:user_5699` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `edit_version` | `1` |  |
| `ext` | `{}` |  |
| `from` | `user_5507` | 发送方 user_id |
| `msg_id` | `342927844487200768` | 服务端分配的全局消息 ID（雪花） |
| `msg_type` | `MSG_TEXT` | 消息内容类型：MSG_TEXT/MSG_STREAM 等 |
| `timestamp` | `1785827569427` |  |
| `to` | `user_5699` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |

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
      "conv_id": "p:user_5507:user_5699",
      "edit_version": 1,
      "ext": {},
      "from": "user_5507",
      "msg_id": "342927844487200768",
      "msg_type": "MSG_TEXT",
      "timestamp": 1785827569427,
      "to": "user_5699"
    },
    "route_key": "",
    "seq": 3,
    "trace_id": "",
    "ts": 1785827569427,
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
| `ts` | `1785827569451` | 发送时间戳（毫秒） |
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
    "ts": 1785827569451,
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
| `ts` | `1785827569453` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `action` | `typing` | 透传 action 名 |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `conv_id` | `` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `data` | `{"typing":true}` | 透传 JSON 字符串 |
| `from` | `user_2852` | 发送方 user_id |
| `persist` | `false` |  |
| `to` | `user_4741` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |
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
      "from": "user_2852",
      "persist": "false",
      "to": "user_4741",
      "ttl_sec": 0
    },
    "route_key": "",
    "seq": 0,
    "trace_id": "",
    "ts": 1785827569453,
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
| `ts` | `1785827569368` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `client_msg_id` | `99fb258be8665887` | 消息级幂等 ID（业务去重） |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `msg_id` | `342927844252319744` | 服务端分配的全局消息 ID（雪花） |
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
      "client_msg_id": "99fb258be8665887",
      "conv_seq": 1,
      "msg_id": "342927844252319744",
      "status": "ACK_SERVER_RECEIVED"
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785827569368,
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
| `cid` | `99fb258be8665887` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `101` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `p:user_4645:user_999` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `0` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785827569368` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `burn_after_read` | `true` |  |
| `burn_ttl_sec` | `0` |  |
| `burned` | `false` |  |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `client_msg_id` | `99fb258be8665887` | 消息级幂等 ID（业务去重） |
| `content` | `secret` | 消息体；MSG_TEXT 为 UTF-8 文本；MSG_STREAM 为 StreamContent 结构 |
| `conv_id` | `p:user_4645:user_999` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `edit_version` | `0` |  |
| `ext` | `{}` |  |
| `from` | `user_999` | 发送方 user_id |
| `inbox_seq` | `0` |  |
| `msg_id` | `342927844252319744` | 服务端分配的全局消息 ID（雪花） |
| `msg_type` | `MSG_TEXT` | 消息内容类型：MSG_TEXT/MSG_STREAM 等 |
| `priority` | `MSG_PRIORITY_NORMAL` |  |
| `recalled` | `false` |  |
| `server_time` | `1785827569362` | 服务端当前时间（毫秒） |
| `target_users` | `[]` |  |
| `to` | `user_4645` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "B",
  "case": "extensions_test/阅后即焚：已读后双方收到 BURN_PUSH",
  "direction": "↓ WS CMD_MSG_PUSH",
  "note": "↓ WS CMD_MSG_PUSH",
  "packet": {
    "cid": "99fb258be8665887",
    "cmd": 101,
    "cmd_name": "CMD_MSG_PUSH",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "burn_after_read": "true",
      "burn_ttl_sec": 0,
      "burned": "false",
      "chat_type": "CHAT_PRIVATE",
      "client_msg_id": "99fb258be8665887",
      "content": "secret",
      "conv_id": "p:user_4645:user_999",
      "conv_seq": 1,
      "edit_version": 0,
      "ext": {},
      "from": "user_999",
      "inbox_seq": 0,
      "msg_id": "342927844252319744",
      "msg_type": "MSG_TEXT",
      "priority": "MSG_PRIORITY_NORMAL",
      "recalled": "false",
      "server_time": 1785827569362,
      "target_users": [],
      "to": "user_4645"
    },
    "route_key": "p:user_4645:user_999",
    "seq": 0,
    "trace_id": "",
    "ts": 1785827569368,
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
| `ts` | `1785827569368` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `conv_id` | `p:user_4645:user_999` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `from` | `user_4645` | 发送方 user_id |
| `msg_id` | `342927844252319744` | 服务端分配的全局消息 ID（雪花） |
| `timestamp` | `0` |  |
| `to` | `user_999` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |
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
      "conv_id": "p:user_4645:user_999",
      "conv_seq": 1,
      "from": "user_4645",
      "msg_id": "342927844252319744",
      "timestamp": 0,
      "to": "user_999",
      "unread_count": null
    },
    "route_key": "",
    "seq": 3,
    "trace_id": "",
    "ts": 1785827569368,
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
| `route_key` | `p:user_4645:user_999` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `0` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785827569384` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `burn_ttl_sec` | `0` |  |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `conv_id` | `p:user_4645:user_999` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `from` | `user_999` | 发送方 user_id |
| `msg_id` | `342927844252319744` | 服务端分配的全局消息 ID（雪花） |
| `timestamp` | `1785827569383` |  |
| `to` | `user_4645` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |

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
      "conv_id": "p:user_4645:user_999",
      "from": "user_999",
      "msg_id": "342927844252319744",
      "timestamp": 1785827569383,
      "to": "user_4645"
    },
    "route_key": "p:user_4645:user_999",
    "seq": 0,
    "trace_id": "",
    "ts": 1785827569384,
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
| `ts` | `1785827565257` | 发送时间戳（毫秒） |
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
    "ts": 1785827565257,
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
| `ts` | `1785827565263` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `request_id` | `fr932` | 好友请求 ID |
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
      "request_id": "fr932",
      "status": "FRIEND_STATUS_PENDING"
    },
    "route_key": "",
    "seq": 3,
    "trace_id": "",
    "ts": 1785827565263,
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
| `ts` | `1785827565264` | 发送时间戳（毫秒） |
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
    "ts": 1785827565264,
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
| `ts` | `1785827565268` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `friend_user_id` | `user_356` |  |
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
      "friend_user_id": "user_356",
      "status": "FRIEND_STATUS_ACCEPTED"
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785827565268,
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
| `ts` | `1785827569740` | 发送时间戳（毫秒） |
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
    "ts": 1785827569740,
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
| `ts` | `1785827569743` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `has_more` | `false` |  |
| `next_cursor` | `` |  |
| `requests` | `[{"from_avatar":"","from_nickname":"","from_user_id":"user_1954","message":"","request_id":"fr2274","status":"FRIEND_REQUEST_STATUS_PENDING","timestamp":1785827569739,"to_avatar":"","to_nickname":"","to_user_id":"user_2114"}]` |  |

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
          "from_user_id": "user_1954",
          "message": "",
          "request_id": "fr2274",
          "status": "FRIEND_REQUEST_STATUS_PENDING",
          "timestamp": 1785827569739,
          "to_avatar": "",
          "to_nickname": "",
          "to_user_id": "user_2114"
        }
      ]
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785827569743,
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
| `ts` | `1785827569758` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `user_id` | `user_6725` | 业务用户 ID |

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
      "user_id": "user_6725"
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785827569758,
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
| `ts` | `1785827569759` | 发送时间戳（毫秒） |
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
    "ts": 1785827569759,
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
| `ts` | `1785827569762` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `user_id` | `user_6725` | 业务用户 ID |

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
      "user_id": "user_6725"
    },
    "route_key": "",
    "seq": 4,
    "trace_id": "",
    "ts": 1785827569762,
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
| `ts` | `1785827569719` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `request_id` | `fr6533` | 好友请求 ID |
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
      "request_id": "fr6533",
      "status": "FRIEND_STATUS_PENDING"
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785827569719,
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
| `ts` | `1785827569723` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `friend_user_id` | `user_6213` |  |

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
      "friend_user_id": "user_6213"
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785827569723,
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
| `ts` | `1785827569692` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `request_id` | `fr1858` | 好友请求 ID |
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
      "request_id": "fr1858",
      "status": "FRIEND_STATUS_PENDING"
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785827569692,
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
| `ts` | `1785827569695` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `friend_user_id` | `user_1352` |  |
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
      "friend_user_id": "user_1352",
      "status": "FRIEND_STATUS_ACCEPTED"
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785827569695,
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
| `ts` | `1785827569699` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `friends` | `[{"avatar":"","created_at":1785827569692,"ext":"","nickname":"","remark":"","status":"FRIEND_STATUS_ACCEPTED","user_id":"user_1698"}]` |  |
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
          "created_at": 1785827569692,
          "ext": "",
          "nickname": "",
          "remark": "",
          "status": "FRIEND_STATUS_ACCEPTED",
          "user_id": "user_1698"
        }
      ],
      "has_more": "false",
      "next_cursor": ""
    },
    "route_key": "",
    "seq": 3,
    "trace_id": "",
    "ts": 1785827569699,
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
| `ts` | `1785827569699` | 发送时间戳（毫秒） |
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
    "ts": 1785827569699,
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
| `ts` | `1785827569701` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `friend_user_id` | `user_1698` |  |
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
      "friend_user_id": "user_1698",
      "remark": "buddy"
    },
    "route_key": "",
    "seq": 4,
    "trace_id": "",
    "ts": 1785827569701,
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
| `ts` | `1785827569704` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `friend_user_id` | `user_1698` |  |

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
      "friend_user_id": "user_1698"
    },
    "route_key": "",
    "seq": 5,
    "trace_id": "",
    "ts": 1785827569704,
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
| `ts` | `1785827569558` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `conv_id` | `g:g-5445` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `created_at` | `1785827569558` |  |
| `group_id` | `g-5445` | 群 ID |
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
      "conv_id": "g:g-5445",
      "created_at": 1785827569558,
      "group_id": "g-5445",
      "name": "test-group"
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785827569558,
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
| `ts` | `1785827569563` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `conv_id` | `g:g-5445` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `group_id` | `g-5445` | 群 ID |
| `member_uids` | `["user_7107"]` |  |
| `operator_uid` | `user_7107` |  |
| `timestamp` | `1785827569563` |  |

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
      "conv_id": "g:g-5445",
      "group_id": "g-5445",
      "member_uids": [
        "user_7107"
      ],
      "operator_uid": "user_7107",
      "timestamp": 1785827569563
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785827569563,
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
| `ts` | `1785827569568` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `conv_id` | `g:g-5445` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `group_id` | `g-5445` | 群 ID |
| `member_uid` | `user_6947` |  |
| `new_role` | `GROUP_MEMBER_ROLE_ADMIN` |  |
| `operator_uid` | `user_1479` |  |
| `timestamp` | `1785827569567` |  |

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
      "conv_id": "g:g-5445",
      "group_id": "g-5445",
      "member_uid": "user_6947",
      "new_role": "GROUP_MEMBER_ROLE_ADMIN",
      "operator_uid": "user_1479",
      "timestamp": 1785827569567
    },
    "route_key": "",
    "seq": 3,
    "trace_id": "",
    "ts": 1785827569568,
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
| `ts` | `1785827569570` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `conv_id` | `g:g-5445` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `group_id` | `g-5445` | 群 ID |
| `member_uid` | `user_6947` |  |
| `new_role` | `GROUP_MEMBER_ROLE_MEMBER` |  |
| `operator_uid` | `user_1479` |  |
| `timestamp` | `1785827569570` |  |

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
      "conv_id": "g:g-5445",
      "group_id": "g-5445",
      "member_uid": "user_6947",
      "new_role": "GROUP_MEMBER_ROLE_MEMBER",
      "operator_uid": "user_1479",
      "timestamp": 1785827569570
    },
    "route_key": "",
    "seq": 4,
    "trace_id": "",
    "ts": 1785827569570,
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
| `route_key` | `g-5445` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `5` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785827569579` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `client_msg_id` | `800f3ac2706c6ec0` | 消息级幂等 ID（业务去重） |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `msg_id` | `342927845137317888` | 服务端分配的全局消息 ID（雪花） |
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
      "client_msg_id": "800f3ac2706c6ec0",
      "conv_seq": 1,
      "msg_id": "342927845137317888",
      "status": "ACK_SERVER_RECEIVED"
    },
    "route_key": "g-5445",
    "seq": 5,
    "trace_id": "",
    "ts": 1785827569579,
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
| `cid` | `800f3ac2706c6ec0` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `101` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `g:g-5445` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `0` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785827569579` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `burn_after_read` | `false` |  |
| `burn_ttl_sec` | `0` |  |
| `burned` | `false` |  |
| `chat_type` | `CHAT_GROUP` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `client_msg_id` | `800f3ac2706c6ec0` | 消息级幂等 ID（业务去重） |
| `content` | `group-hi` | 消息体；MSG_TEXT 为 UTF-8 文本；MSG_STREAM 为 StreamContent 结构 |
| `conv_id` | `g:g-5445` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `edit_version` | `0` |  |
| `ext` | `{}` |  |
| `from` | `user_1479` | 发送方 user_id |
| `inbox_seq` | `0` |  |
| `msg_id` | `342927845137317888` | 服务端分配的全局消息 ID（雪花） |
| `msg_type` | `MSG_TEXT` | 消息内容类型：MSG_TEXT/MSG_STREAM 等 |
| `priority` | `MSG_PRIORITY_NORMAL` |  |
| `recalled` | `false` |  |
| `server_time` | `1785827569572` | 服务端当前时间（毫秒） |
| `target_users` | `[]` |  |
| `to` | `g-5445` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "member",
  "case": "group_test/群生命周期与群消息",
  "direction": "↓ WS CMD_MSG_PUSH",
  "note": "↓ WS CMD_MSG_PUSH",
  "packet": {
    "cid": "800f3ac2706c6ec0",
    "cmd": 101,
    "cmd_name": "CMD_MSG_PUSH",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "burn_after_read": "false",
      "burn_ttl_sec": 0,
      "burned": "false",
      "chat_type": "CHAT_GROUP",
      "client_msg_id": "800f3ac2706c6ec0",
      "content": "group-hi",
      "conv_id": "g:g-5445",
      "conv_seq": 1,
      "edit_version": 0,
      "ext": {},
      "from": "user_1479",
      "inbox_seq": 0,
      "msg_id": "342927845137317888",
      "msg_type": "MSG_TEXT",
      "priority": "MSG_PRIORITY_NORMAL",
      "recalled": "false",
      "server_time": 1785827569572,
      "target_users": [],
      "to": "g-5445"
    },
    "route_key": "g:g-5445",
    "seq": 0,
    "trace_id": "",
    "ts": 1785827569579,
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
| `ts` | `1785827569583` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `conv_id` | `g:g-5445` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `group_id` | `g-5445` | 群 ID |
| `member_uids` | `["user_7107"]` |  |
| `operator_uid` | `user_7107` |  |
| `timestamp` | `1785827569583` |  |

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
      "conv_id": "g:g-5445",
      "group_id": "g-5445",
      "member_uids": [
        "user_7107"
      ],
      "operator_uid": "user_7107",
      "timestamp": 1785827569583
    },
    "route_key": "",
    "seq": 3,
    "trace_id": "",
    "ts": 1785827569583,
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
| `ts` | `1785827569588` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `conv_id` | `g:g-5445` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `group_id` | `g-5445` | 群 ID |
| `new_owner_uid` | `user_6947` |  |
| `old_owner_uid` | `user_1479` |  |
| `timestamp` | `1785827569587` |  |

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
      "conv_id": "g:g-5445",
      "group_id": "g-5445",
      "new_owner_uid": "user_6947",
      "old_owner_uid": "user_1479",
      "timestamp": 1785827569587
    },
    "route_key": "",
    "seq": 6,
    "trace_id": "",
    "ts": 1785827569588,
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
| `ts` | `1785827569590` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `announcement` | `ann` |  |
| `conv_id` | `g:g-5445` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `group_id` | `g-5445` | 群 ID |
| `name` | `renamed` |  |
| `operator_uid` | `user_6947` |  |
| `timestamp` | `1785827569589` |  |

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
      "conv_id": "g:g-5445",
      "group_id": "g-5445",
      "name": "renamed",
      "operator_uid": "user_6947",
      "timestamp": 1785827569589
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785827569590,
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
| `ts` | `1785827569593` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `conv_id` | `g:g-5445` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `group_id` | `g-5445` | 群 ID |
| `member_uids` | `["user_5413"]` |  |
| `operator_uid` | `user_6947` |  |
| `timestamp` | `1785827569593` |  |

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
      "conv_id": "g:g-5445",
      "group_id": "g-5445",
      "member_uids": [
        "user_5413"
      ],
      "operator_uid": "user_6947",
      "timestamp": 1785827569593
    },
    "route_key": "",
    "seq": 3,
    "trace_id": "",
    "ts": 1785827569593,
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
| `ts` | `1785827569597` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `conv_id` | `g:g-5445` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `group_id` | `g-5445` | 群 ID |
| `member_uids` | `["user_1479"]` |  |
| `operator_uid` | `user_6947` |  |
| `timestamp` | `1785827569597` |  |

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
      "conv_id": "g:g-5445",
      "group_id": "g-5445",
      "member_uids": [
        "user_1479"
      ],
      "operator_uid": "user_6947",
      "timestamp": 1785827569597
    },
    "route_key": "",
    "seq": 4,
    "trace_id": "",
    "ts": 1785827569597,
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
| `ts` | `1785827569600` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `conv_id` | `g:g-5445` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `group_id` | `g-5445` | 群 ID |
| `operator_uid` | `user_6947` |  |
| `reason` | `` | 踢下线/撤回等原因 |
| `timestamp` | `1785827569600` |  |

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
      "conv_id": "g:g-5445",
      "group_id": "g-5445",
      "operator_uid": "user_6947",
      "reason": "",
      "timestamp": 1785827569600
    },
    "route_key": "",
    "seq": 5,
    "trace_id": "",
    "ts": 1785827569600,
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
| `ts` | `1785827565227` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `conv_id` | `p:user_260:user_518` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
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
      "conv_id": "p:user_260:user_518",
      "cursor": 0,
      "limit": 50
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785827565227,
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
| `ts` | `1785827565230` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `has_more` | `false` |  |
| `messages` | `[{"burn_after_read":"false","burn_ttl_sec":0,"burned":"false","chat_type":"CHAT_PRIVATE","client_msg_id":"cm-582","content":"offline-msg","conv_id":"p:user_260:user_518","conv_seq":1,"edit_version":0,"ext":{},"from":"user_260","inbox_seq":1,"msg_id":"342927826799820800","msg_type":"MSG_TEXT","priority":"MSG_PRIORITY_NORMAL","recalled":"false","server_time":1785827565202,"target_users":[],"to":"user_518"}]` |  |
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
          "client_msg_id": "cm-582",
          "content": "offline-msg",
          "conv_id": "p:user_260:user_518",
          "conv_seq": 1,
          "edit_version": 0,
          "ext": {},
          "from": "user_260",
          "inbox_seq": 1,
          "msg_id": "342927826799820800",
          "msg_type": "MSG_TEXT",
          "priority": "MSG_PRIORITY_NORMAL",
          "recalled": "false",
          "server_time": 1785827565202,
          "target_users": [],
          "to": "user_518"
        }
      ],
      "next_cursor": 1
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785827565230,
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
| `ts` | `1785827569246` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `message` | `{"burn_after_read":"false","burn_ttl_sec":0,"burned":"false","chat_type":"CHAT_PRIVATE","client_msg_id":"cm-4421","content":"hi-b","conv_id":"","conv_seq":0,"edit_version":0,"ext":{},"from":"user_1988","inbox_seq":0,"msg_id":"","msg_type":"MSG_TEXT","priority":"MSG_PRIORITY_NORMAL","recalled":"false","server_time":0,"target_users":[],"to":"user_5315"}` |  |

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
        "client_msg_id": "cm-4421",
        "content": "hi-b",
        "conv_id": "",
        "conv_seq": 0,
        "edit_version": 0,
        "ext": {},
        "from": "user_1988",
        "inbox_seq": 0,
        "msg_id": "",
        "msg_type": "MSG_TEXT",
        "priority": "MSG_PRIORITY_NORMAL",
        "recalled": "false",
        "server_time": 0,
        "target_users": [],
        "to": "user_5315"
      }
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785827569246,
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
| `ts` | `1785827569275` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `client_msg_id` | `cm-4421` | 消息级幂等 ID（业务去重） |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `msg_id` | `342927843811917824` | 服务端分配的全局消息 ID（雪花） |
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
      "client_msg_id": "cm-4421",
      "conv_seq": 1,
      "msg_id": "342927843811917824",
      "status": "ACK_SERVER_RECEIVED"
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785827569275,
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
| `cid` | `cm-4421` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `101` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `p:user_1988:user_5315` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `0` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785827569275` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `burn_after_read` | `false` |  |
| `burn_ttl_sec` | `0` |  |
| `burned` | `false` |  |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `client_msg_id` | `cm-4421` | 消息级幂等 ID（业务去重） |
| `content` | `hi-b` | 消息体；MSG_TEXT 为 UTF-8 文本；MSG_STREAM 为 StreamContent 结构 |
| `conv_id` | `p:user_1988:user_5315` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `edit_version` | `0` |  |
| `ext` | `{}` |  |
| `from` | `user_1988` | 发送方 user_id |
| `inbox_seq` | `0` |  |
| `msg_id` | `342927843811917824` | 服务端分配的全局消息 ID（雪花） |
| `msg_type` | `MSG_TEXT` | 消息内容类型：MSG_TEXT/MSG_STREAM 等 |
| `priority` | `MSG_PRIORITY_NORMAL` |  |
| `recalled` | `false` |  |
| `server_time` | `1785827569258` | 服务端当前时间（毫秒） |
| `target_users` | `[]` |  |
| `to` | `user_5315` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "B",
  "case": "private_message_test/A 发单聊 → B 收 PUSH + 客户端 ACK",
  "direction": "↓ WS CMD_MSG_PUSH",
  "note": "↓ WS CMD_MSG_PUSH",
  "packet": {
    "cid": "cm-4421",
    "cmd": 101,
    "cmd_name": "CMD_MSG_PUSH",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "burn_after_read": "false",
      "burn_ttl_sec": 0,
      "burned": "false",
      "chat_type": "CHAT_PRIVATE",
      "client_msg_id": "cm-4421",
      "content": "hi-b",
      "conv_id": "p:user_1988:user_5315",
      "conv_seq": 1,
      "edit_version": 0,
      "ext": {},
      "from": "user_1988",
      "inbox_seq": 0,
      "msg_id": "342927843811917824",
      "msg_type": "MSG_TEXT",
      "priority": "MSG_PRIORITY_NORMAL",
      "recalled": "false",
      "server_time": 1785827569258,
      "target_users": [],
      "to": "user_5315"
    },
    "route_key": "p:user_1988:user_5315",
    "seq": 0,
    "trace_id": "",
    "ts": 1785827569275,
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
| `ts` | `1785827569276` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `client_msg_id` | `cm-4421` | 消息级幂等 ID（业务去重） |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `msg_id` | `342927843811917824` | 服务端分配的全局消息 ID（雪花） |
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
      "client_msg_id": "cm-4421",
      "conv_seq": 1,
      "msg_id": "342927843811917824",
      "status": "ACK_CLIENT_RECEIVED"
    },
    "route_key": "",
    "seq": 5,
    "trace_id": "",
    "ts": 1785827569276,
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
| `to` | `user_4613` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |

**HTTP 响应体（节选）**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `client_msg_id` | `10f42bf856ed31a9` | 消息级幂等 ID（业务去重） |
| `conv_id` | `p:user_1062:user_4613` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `duplicate` | `false` |  |
| `msg_id` | `342927844172627968` | 服务端分配的全局消息 ID（雪花） |
| `server_time` | `1785827569343` | 服务端当前时间（毫秒） |
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
      "to": "user_4613"
    },
    "response": {
      "body": {
        "client_msg_id": "10f42bf856ed31a9",
        "conv_id": "p:user_1062:user_4613",
        "conv_seq": 1,
        "duplicate": false,
        "msg_id": "342927844172627968",
        "server_time": 1785827569343,
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
| `cid` | `10f42bf856ed31a9` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `101` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `p:user_1062:user_4613` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `0` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `lt-2c811fb810c0` | 链路追踪 ID |
| `ts` | `1785827569349` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `burn_after_read` | `false` |  |
| `burn_ttl_sec` | `0` |  |
| `burned` | `false` |  |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `client_msg_id` | `10f42bf856ed31a9` | 消息级幂等 ID（业务去重） |
| `content` | `rest-path` | 消息体；MSG_TEXT 为 UTF-8 文本；MSG_STREAM 为 StreamContent 结构 |
| `conv_id` | `p:user_1062:user_4613` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `edit_version` | `0` |  |
| `ext` | `{}` |  |
| `from` | `user_1062` | 发送方 user_id |
| `inbox_seq` | `0` |  |
| `msg_id` | `342927844172627968` | 服务端分配的全局消息 ID（雪花） |
| `msg_type` | `MSG_TEXT` | 消息内容类型：MSG_TEXT/MSG_STREAM 等 |
| `priority` | `MSG_PRIORITY_NORMAL` |  |
| `recalled` | `false` |  |
| `server_time` | `1785827569343` | 服务端当前时间（毫秒） |
| `target_users` | `[]` |  |
| `to` | `user_4613` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "B",
  "case": "private_message_test/REST 发消息双通道",
  "direction": "↓ WS CMD_MSG_PUSH",
  "note": "↓ WS CMD_MSG_PUSH",
  "packet": {
    "cid": "10f42bf856ed31a9",
    "cmd": 101,
    "cmd_name": "CMD_MSG_PUSH",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "burn_after_read": "false",
      "burn_ttl_sec": 0,
      "burned": "false",
      "chat_type": "CHAT_PRIVATE",
      "client_msg_id": "10f42bf856ed31a9",
      "content": "rest-path",
      "conv_id": "p:user_1062:user_4613",
      "conv_seq": 1,
      "edit_version": 0,
      "ext": {},
      "from": "user_1062",
      "inbox_seq": 0,
      "msg_id": "342927844172627968",
      "msg_type": "MSG_TEXT",
      "priority": "MSG_PRIORITY_NORMAL",
      "recalled": "false",
      "server_time": 1785827569343,
      "target_users": [],
      "to": "user_4613"
    },
    "route_key": "p:user_1062:user_4613",
    "seq": 0,
    "trace_id": "lt-2c811fb810c0",
    "ts": 1785827569349,
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
| `ts` | `1785827569318` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `message` | `{"burn_after_read":"false","burn_ttl_sec":0,"burned":"false","chat_type":"CHAT_PRIVATE","client_msg_id":"idem-2756","content":"once","conv_id":"","conv_seq":0,"edit_version":0,"ext":{},"from":"user_2436","inbox_seq":0,"msg_id":"","msg_type":"MSG_TEXT","priority":"MSG_PRIORITY_NORMAL","recalled":"false","server_time":0,"target_users":[],"to":"user_4517"}` |  |

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
        "client_msg_id": "idem-2756",
        "content": "once",
        "conv_id": "",
        "conv_seq": 0,
        "edit_version": 0,
        "ext": {},
        "from": "user_2436",
        "inbox_seq": 0,
        "msg_id": "",
        "msg_type": "MSG_TEXT",
        "priority": "MSG_PRIORITY_NORMAL",
        "recalled": "false",
        "server_time": 0,
        "target_users": [],
        "to": "user_4517"
      }
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785827569318,
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
| `ts` | `1785827569327` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `client_msg_id` | `idem-2756` | 消息级幂等 ID（业务去重） |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `msg_id` | `342927844084547584` | 服务端分配的全局消息 ID（雪花） |
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
      "client_msg_id": "idem-2756",
      "conv_seq": 1,
      "msg_id": "342927844084547584",
      "status": "ACK_SERVER_RECEIVED"
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785827569327,
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
| `ts` | `1785827569328` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `client_msg_id` | `idem-2756` | 消息级幂等 ID（业务去重） |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `msg_id` | `342927844084547584` | 服务端分配的全局消息 ID（雪花） |
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
      "client_msg_id": "idem-2756",
      "conv_seq": 1,
      "msg_id": "342927844084547584",
      "status": "ACK_SERVER_RECEIVED"
    },
    "route_key": "",
    "seq": 3,
    "trace_id": "",
    "ts": 1785827569328,
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
| `ts` | `1785827569307` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `acks` | `[{"client_msg_id":"cm-2404","conv_seq":1,"msg_id":"342927843996467200","status":"ACK_CLIENT_RECEIVED"}]` |  |

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
          "client_msg_id": "cm-2404",
          "conv_seq": 1,
          "msg_id": "342927843996467200",
          "status": "ACK_CLIENT_RECEIVED"
        }
      ]
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785827569307,
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
| `ts` | `1785827565340` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `conv_id` | `r:room-3589` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `created_at` | `1785827565335` |  |
| `name` | `lobby` |  |
| `room_id` | `room-3589` | 聊天室 ID |

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
      "conv_id": "r:room-3589",
      "created_at": 1785827565335,
      "name": "lobby",
      "room_id": "room-3589"
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785827565340,
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
| `ts` | `1785827565344` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `conv_id` | `r:room-3589` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `member_uids` | `["user_3429"]` |  |
| `operator_uid` | `user_3429` |  |
| `room_id` | `room-3589` | 聊天室 ID |
| `timestamp` | `1785827565343` |  |

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
      "conv_id": "r:room-3589",
      "member_uids": [
        "user_3429"
      ],
      "operator_uid": "user_3429",
      "room_id": "room-3589",
      "timestamp": 1785827565343
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785827565344,
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
| `ts` | `1785827565344` | 发送时间戳（毫秒） |
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
    "ts": 1785827565344,
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
| `ts` | `1785827565347` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `conv_id` | `r:room-3589` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `name` | `lobby-2` |  |
| `operator_uid` | `user_1030` |  |
| `room_id` | `room-3589` | 聊天室 ID |
| `timestamp` | `1785827565346` |  |

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
      "conv_id": "r:room-3589",
      "name": "lobby-2",
      "operator_uid": "user_1030",
      "room_id": "room-3589",
      "timestamp": 1785827565346
    },
    "route_key": "",
    "seq": 3,
    "trace_id": "",
    "ts": 1785827565347,
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
| `route_key` | `room-3589` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `4` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785827565348` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `client_msg_id` | `a6a401a1657faea4` | 消息级幂等 ID（业务去重） |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `msg_id` | `342927827416383488` | 服务端分配的全局消息 ID（雪花） |
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
      "client_msg_id": "a6a401a1657faea4",
      "conv_seq": 1,
      "msg_id": "342927827416383488",
      "status": "ACK_SERVER_RECEIVED"
    },
    "route_key": "room-3589",
    "seq": 4,
    "trace_id": "",
    "ts": 1785827565348,
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
| `cid` | `a6a401a1657faea4` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `101` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `r:room-3589` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `0` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785827565348` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `burn_after_read` | `false` |  |
| `burn_ttl_sec` | `0` |  |
| `burned` | `false` |  |
| `chat_type` | `CHAT_ROOM` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `client_msg_id` | `a6a401a1657faea4` | 消息级幂等 ID（业务去重） |
| `content` | `room-msg` | 消息体；MSG_TEXT 为 UTF-8 文本；MSG_STREAM 为 StreamContent 结构 |
| `conv_id` | `r:room-3589` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `edit_version` | `0` |  |
| `ext` | `{}` |  |
| `from` | `user_1030` | 发送方 user_id |
| `inbox_seq` | `0` |  |
| `msg_id` | `342927827416383488` | 服务端分配的全局消息 ID（雪花） |
| `msg_type` | `MSG_TEXT` | 消息内容类型：MSG_TEXT/MSG_STREAM 等 |
| `priority` | `MSG_PRIORITY_NORMAL` |  |
| `recalled` | `false` |  |
| `server_time` | `1785827565348` | 服务端当前时间（毫秒） |
| `target_users` | `[]` |  |
| `to` | `room-3589` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "guest",
  "case": "room_test/聊天室生命周期与广播",
  "direction": "↓ WS CMD_MSG_PUSH",
  "note": "↓ WS CMD_MSG_PUSH",
  "packet": {
    "cid": "a6a401a1657faea4",
    "cmd": 101,
    "cmd_name": "CMD_MSG_PUSH",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "burn_after_read": "false",
      "burn_ttl_sec": 0,
      "burned": "false",
      "chat_type": "CHAT_ROOM",
      "client_msg_id": "a6a401a1657faea4",
      "content": "room-msg",
      "conv_id": "r:room-3589",
      "conv_seq": 1,
      "edit_version": 0,
      "ext": {},
      "from": "user_1030",
      "inbox_seq": 0,
      "msg_id": "342927827416383488",
      "msg_type": "MSG_TEXT",
      "priority": "MSG_PRIORITY_NORMAL",
      "recalled": "false",
      "server_time": 1785827565348,
      "target_users": [],
      "to": "room-3589"
    },
    "route_key": "r:room-3589",
    "seq": 0,
    "trace_id": "",
    "ts": 1785827565348,
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
| `ts` | `1785827565348` | 发送时间戳（毫秒） |
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
    "payload_raw_bytes": 28,
    "route_key": "",
    "seq": 8,
    "trace_id": "",
    "ts": 1785827565348,
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
| `ts` | `1785827565352` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `conv_id` | `r:room-3589` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `member_uids` | `["user_3429"]` |  |
| `operator_uid` | `user_1030` |  |
| `room_id` | `room-3589` | 聊天室 ID |
| `timestamp` | `1785827565352` |  |

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
      "conv_id": "r:room-3589",
      "member_uids": [
        "user_3429"
      ],
      "operator_uid": "user_1030",
      "room_id": "room-3589",
      "timestamp": 1785827565352
    },
    "route_key": "",
    "seq": 5,
    "trace_id": "",
    "ts": 1785827565352,
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
| `ts` | `1785827565354` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `conv_id` | `r:room-3589` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `member_uids` | `["user_3429"]` |  |
| `operator_uid` | `user_3429` |  |
| `room_id` | `room-3589` | 聊天室 ID |
| `timestamp` | `1785827565354` |  |

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
      "conv_id": "r:room-3589",
      "member_uids": [
        "user_3429"
      ],
      "operator_uid": "user_3429",
      "room_id": "room-3589",
      "timestamp": 1785827565354
    },
    "route_key": "",
    "seq": 3,
    "trace_id": "",
    "ts": 1785827565354,
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
| `ts` | `1785827565380` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `conv_id` | `r:room-3589` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `member_uids` | `["user_3429"]` |  |
| `operator_uid` | `user_3429` |  |
| `room_id` | `room-3589` | 聊天室 ID |
| `timestamp` | `1785827565380` |  |

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
      "conv_id": "r:room-3589",
      "member_uids": [
        "user_3429"
      ],
      "operator_uid": "user_3429",
      "room_id": "room-3589",
      "timestamp": 1785827565380
    },
    "route_key": "",
    "seq": 4,
    "trace_id": "",
    "ts": 1785827565380,
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
| `ts` | `1785827565388` | 发送时间戳（毫秒） |
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
    "ts": 1785827565388,
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
| `ts` | `1785827565405` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `conv_id` | `r:room-3589` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `operator_uid` | `user_1030` |  |
| `reason` | `` | 踢下线/撤回等原因 |
| `room_id` | `room-3589` | 聊天室 ID |
| `timestamp` | `1785827565402` |  |

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
      "conv_id": "r:room-3589",
      "operator_uid": "user_1030",
      "reason": "",
      "room_id": "room-3589",
      "timestamp": 1785827565402
    },
    "route_key": "",
    "seq": 6,
    "trace_id": "",
    "ts": 1785827565405,
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
| `user_id` | `user_1028` | 业务用户 ID |

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
      "user_id": "user_1028"
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
| `trace_id` | `tr-1188` | 链路追踪 ID |
| `ts` | `1785827565290` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `clear_local_data` | `false` |  |
| `kicker` | `` |  |
| `reason` | `e2e` | 踢下线/撤回等原因 |
| `reason_code` | `KICK_REASON_ADMIN_KICK` | KickReason 枚举 |
| `timestamp` | `1785827565289` |  |

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
      "timestamp": 1785827565289
    },
    "route_key": "",
    "seq": 0,
    "trace_id": "tr-1188",
    "ts": 1785827565290,
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
| `ts` | `1785827565316` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `app_key` | `app_demo` | 租户应用标识 |
| `compression_offered` | `[]` |  |
| `device_id` | `d2-1380` | 设备唯一标识 |
| `device_model` | `` |  |
| `device_name` | `` |  |
| `network` | `` |  |
| `os` | `` |  |
| `platform` | `ios` | 客户端平台：ios/android/web/desktop |
| `sdk_ver` | `0.1.0` | SDK 版本号 |
| `token` | `Ibr-sUeCVoCnDAo_7wMzhH4uRWNgMLaMypqfTubFtjU` | WS 鉴权 token（与 REST access_token 相同） |
| `user_id` | `user_648` | 业务用户 ID |

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
      "device_id": "d2-1380",
      "device_model": "",
      "device_name": "",
      "network": "",
      "os": "",
      "platform": "ios",
      "sdk_ver": "0.1.0",
      "token": "Ibr-sUeCVoCnDAo_7wMzhH4uRWNgMLaMypqfTubFtjU",
      "user_id": "user_648"
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785827565316,
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
| `ts` | `1785827565317` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `clear_local_data` | `false` |  |
| `kicker` | `` |  |
| `reason` | `device_limit` | 踢下线/撤回等原因 |
| `reason_code` | `KICK_REASON_DEVICE_LIMIT` | KickReason 枚举 |
| `timestamp` | `1785827565317` |  |

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
      "timestamp": 1785827565317
    },
    "route_key": "",
    "seq": 0,
    "trace_id": "",
    "ts": 1785827565317,
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
| `ts` | `1785827565301` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `app_key` | `app_demo` | 租户应用标识 |
| `compression_offered` | `[]` |  |
| `device_id` | `d2-770` | 设备唯一标识 |
| `device_model` | `` |  |
| `device_name` | `` |  |
| `network` | `` |  |
| `os` | `` |  |
| `platform` | `ios` | 客户端平台：ios/android/web/desktop |
| `sdk_ver` | `0.1.0` | SDK 版本号 |
| `token` | `JGB5sGuy1vy1i7gPey7Z5VNpVNCQ1hENZvnIKq7n3uM` | WS 鉴权 token（与 REST access_token 相同） |
| `user_id` | `user_546` | 业务用户 ID |

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
      "device_id": "d2-770",
      "device_model": "",
      "device_name": "",
      "network": "",
      "os": "",
      "platform": "ios",
      "sdk_ver": "0.1.0",
      "token": "JGB5sGuy1vy1i7gPey7Z5VNpVNCQ1hENZvnIKq7n3uM",
      "user_id": "user_546"
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785827565301,
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
| `ts` | `1785827565304` | 发送时间戳（毫秒） |
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
    "ts": 1785827565304,
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
| `cid` | `sm-5797` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `101` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `p:user_1288:user_5637` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `0` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785827569622` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `burn_after_read` | `false` |  |
| `burn_ttl_sec` | `0` |  |
| `burned` | `false` |  |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `client_msg_id` | `sm-5797` | 消息级幂等 ID（业务去重） |
| `content` | `{"chunk":"","content_type":"text/plain","metadata":{},"sequence":1,"status":"STREAM_STATUS_START","stream_id":"st-5765"}` | 消息体；MSG_TEXT 为 UTF-8 文本；MSG_STREAM 为 StreamContent 结构 |
| `conv_id` | `p:user_1288:user_5637` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `conv_seq` | `1` | 会话内单调排序位点 |
| `edit_version` | `0` |  |
| `ext` | `{}` |  |
| `from` | `user_1288` | 发送方 user_id |
| `inbox_seq` | `0` |  |
| `msg_id` | `342927845317672960` | 服务端分配的全局消息 ID（雪花） |
| `msg_type` | `MSG_STREAM` | 消息内容类型：MSG_TEXT/MSG_STREAM 等 |
| `priority` | `MSG_PRIORITY_NORMAL` |  |
| `recalled` | `false` |  |
| `server_time` | `1785827569616` | 服务端当前时间（毫秒） |
| `target_users` | `[]` |  |
| `to` | `user_5637` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "B",
  "case": "stream_test/MSG_STREAM 四段推送至对端",
  "direction": "↓ WS CMD_MSG_PUSH (STREAM_STATUS_START)",
  "note": "↓ WS CMD_MSG_PUSH (STREAM_STATUS_START)",
  "packet": {
    "cid": "sm-5797",
    "cmd": 101,
    "cmd_name": "CMD_MSG_PUSH",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "burn_after_read": "false",
      "burn_ttl_sec": 0,
      "burned": "false",
      "chat_type": "CHAT_PRIVATE",
      "client_msg_id": "sm-5797",
      "content": {
        "chunk": "",
        "content_type": "text/plain",
        "metadata": {},
        "sequence": 1,
        "status": "STREAM_STATUS_START",
        "stream_id": "st-5765"
      },
      "conv_id": "p:user_1288:user_5637",
      "conv_seq": 1,
      "edit_version": 0,
      "ext": {},
      "from": "user_1288",
      "inbox_seq": 0,
      "msg_id": "342927845317672960",
      "msg_type": "MSG_STREAM",
      "priority": "MSG_PRIORITY_NORMAL",
      "recalled": "false",
      "server_time": 1785827569616,
      "target_users": [],
      "to": "user_5637"
    },
    "route_key": "p:user_1288:user_5637",
    "seq": 0,
    "trace_id": "",
    "ts": 1785827569622,
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
| `cid` | `sm-5829` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `101` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `p:user_1288:user_5637` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `0` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785827569627` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `burn_after_read` | `false` |  |
| `burn_ttl_sec` | `0` |  |
| `burned` | `false` |  |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `client_msg_id` | `sm-5829` | 消息级幂等 ID（业务去重） |
| `content` | `{"chunk":"Hel","content_type":"text/plain","metadata":{},"sequence":2,"status":"STREAM_STATUS_ONGOING","stream_id":"st-5765"}` | 消息体；MSG_TEXT 为 UTF-8 文本；MSG_STREAM 为 StreamContent 结构 |
| `conv_id` | `p:user_1288:user_5637` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `conv_seq` | `2` | 会话内单调排序位点 |
| `edit_version` | `0` |  |
| `ext` | `{}` |  |
| `from` | `user_1288` | 发送方 user_id |
| `inbox_seq` | `0` |  |
| `msg_id` | `342927845351227392` | 服务端分配的全局消息 ID（雪花） |
| `msg_type` | `MSG_STREAM` | 消息内容类型：MSG_TEXT/MSG_STREAM 等 |
| `priority` | `MSG_PRIORITY_NORMAL` |  |
| `recalled` | `false` |  |
| `server_time` | `1785827569623` | 服务端当前时间（毫秒） |
| `target_users` | `[]` |  |
| `to` | `user_5637` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "B",
  "case": "stream_test/MSG_STREAM 四段推送至对端",
  "direction": "↓ WS CMD_MSG_PUSH (STREAM_STATUS_ONGOING)",
  "note": "↓ WS CMD_MSG_PUSH (STREAM_STATUS_ONGOING)",
  "packet": {
    "cid": "sm-5829",
    "cmd": 101,
    "cmd_name": "CMD_MSG_PUSH",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "burn_after_read": "false",
      "burn_ttl_sec": 0,
      "burned": "false",
      "chat_type": "CHAT_PRIVATE",
      "client_msg_id": "sm-5829",
      "content": {
        "chunk": "Hel",
        "content_type": "text/plain",
        "metadata": {},
        "sequence": 2,
        "status": "STREAM_STATUS_ONGOING",
        "stream_id": "st-5765"
      },
      "conv_id": "p:user_1288:user_5637",
      "conv_seq": 2,
      "edit_version": 0,
      "ext": {},
      "from": "user_1288",
      "inbox_seq": 0,
      "msg_id": "342927845351227392",
      "msg_type": "MSG_STREAM",
      "priority": "MSG_PRIORITY_NORMAL",
      "recalled": "false",
      "server_time": 1785827569623,
      "target_users": [],
      "to": "user_5637"
    },
    "route_key": "p:user_1288:user_5637",
    "seq": 0,
    "trace_id": "",
    "ts": 1785827569627,
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
| `cid` | `sm-5861` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `101` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `p:user_1288:user_5637` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `0` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785827569632` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `burn_after_read` | `false` |  |
| `burn_ttl_sec` | `0` |  |
| `burned` | `false` |  |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `client_msg_id` | `sm-5861` | 消息级幂等 ID（业务去重） |
| `content` | `{"chunk":"lo","content_type":"text/plain","metadata":{},"sequence":3,"status":"STREAM_STATUS_ONGOING","stream_id":"st-5765"}` | 消息体；MSG_TEXT 为 UTF-8 文本；MSG_STREAM 为 StreamContent 结构 |
| `conv_id` | `p:user_1288:user_5637` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `conv_seq` | `3` | 会话内单调排序位点 |
| `edit_version` | `0` |  |
| `ext` | `{}` |  |
| `from` | `user_1288` | 发送方 user_id |
| `inbox_seq` | `0` |  |
| `msg_id` | `342927845376393216` | 服务端分配的全局消息 ID（雪花） |
| `msg_type` | `MSG_STREAM` | 消息内容类型：MSG_TEXT/MSG_STREAM 等 |
| `priority` | `MSG_PRIORITY_NORMAL` |  |
| `recalled` | `false` |  |
| `server_time` | `1785827569629` | 服务端当前时间（毫秒） |
| `target_users` | `[]` |  |
| `to` | `user_5637` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "B",
  "case": "stream_test/MSG_STREAM 四段推送至对端",
  "direction": "↓ WS CMD_MSG_PUSH (STREAM_STATUS_ONGOING)",
  "note": "↓ WS CMD_MSG_PUSH (STREAM_STATUS_ONGOING)",
  "packet": {
    "cid": "sm-5861",
    "cmd": 101,
    "cmd_name": "CMD_MSG_PUSH",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "burn_after_read": "false",
      "burn_ttl_sec": 0,
      "burned": "false",
      "chat_type": "CHAT_PRIVATE",
      "client_msg_id": "sm-5861",
      "content": {
        "chunk": "lo",
        "content_type": "text/plain",
        "metadata": {},
        "sequence": 3,
        "status": "STREAM_STATUS_ONGOING",
        "stream_id": "st-5765"
      },
      "conv_id": "p:user_1288:user_5637",
      "conv_seq": 3,
      "edit_version": 0,
      "ext": {},
      "from": "user_1288",
      "inbox_seq": 0,
      "msg_id": "342927845376393216",
      "msg_type": "MSG_STREAM",
      "priority": "MSG_PRIORITY_NORMAL",
      "recalled": "false",
      "server_time": 1785827569629,
      "target_users": [],
      "to": "user_5637"
    },
    "route_key": "p:user_1288:user_5637",
    "seq": 0,
    "trace_id": "",
    "ts": 1785827569632,
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
| `cid` | `sm-5893` | 请求级幂等 ID；PUSH 时可能携带 client_msg_id |
| `cmd` | `101` | 命令字（CmdType 枚举整数值） |
| `cmd_name` | `CMD_MSG_PUSH` | 命令字名称（文档衍生字段） |
| `compression` | `PAYLOAD_COMPRESSION_NONE` | payload 压缩算法 |
| `route_key` | `p:user_1288:user_5637` | 网关分流键；单聊常为 conv_id，群/室为 group_id/room_id |
| `seq` | `0` | 请求序号；客户端上行单调递增；服务端推送为 0 |
| `trace_id` | `` | 链路追踪 ID |
| `ts` | `1785827569637` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `burn_after_read` | `false` |  |
| `burn_ttl_sec` | `0` |  |
| `burned` | `false` |  |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `client_msg_id` | `sm-5893` | 消息级幂等 ID（业务去重） |
| `content` | `{"chunk":"","content_type":"text/plain","metadata":{},"sequence":4,"status":"STREAM_STATUS_END","stream_id":"st-5765"}` | 消息体；MSG_TEXT 为 UTF-8 文本；MSG_STREAM 为 StreamContent 结构 |
| `conv_id` | `p:user_1288:user_5637` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `conv_seq` | `4` | 会话内单调排序位点 |
| `edit_version` | `0` |  |
| `ext` | `{}` |  |
| `from` | `user_1288` | 发送方 user_id |
| `inbox_seq` | `0` |  |
| `msg_id` | `342927845393170432` | 服务端分配的全局消息 ID（雪花） |
| `msg_type` | `MSG_STREAM` | 消息内容类型：MSG_TEXT/MSG_STREAM 等 |
| `priority` | `MSG_PRIORITY_NORMAL` |  |
| `recalled` | `false` |  |
| `server_time` | `1785827569634` | 服务端当前时间（毫秒） |
| `target_users` | `[]` |  |
| `to` | `user_5637` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |

<details><summary>完整 JSON</summary>

```json
{
  "actor": "B",
  "case": "stream_test/MSG_STREAM 四段推送至对端",
  "direction": "↓ WS CMD_MSG_PUSH (STREAM_STATUS_END)",
  "note": "↓ WS CMD_MSG_PUSH (STREAM_STATUS_END)",
  "packet": {
    "cid": "sm-5893",
    "cmd": 101,
    "cmd_name": "CMD_MSG_PUSH",
    "compression": "PAYLOAD_COMPRESSION_NONE",
    "payload": {
      "burn_after_read": "false",
      "burn_ttl_sec": 0,
      "burned": "false",
      "chat_type": "CHAT_PRIVATE",
      "client_msg_id": "sm-5893",
      "content": {
        "chunk": "",
        "content_type": "text/plain",
        "metadata": {},
        "sequence": 4,
        "status": "STREAM_STATUS_END",
        "stream_id": "st-5765"
      },
      "conv_id": "p:user_1288:user_5637",
      "conv_seq": 4,
      "edit_version": 0,
      "ext": {},
      "from": "user_1288",
      "inbox_seq": 0,
      "msg_id": "342927845393170432",
      "msg_type": "MSG_STREAM",
      "priority": "MSG_PRIORITY_NORMAL",
      "recalled": "false",
      "server_time": 1785827569634,
      "target_users": [],
      "to": "user_5637"
    },
    "route_key": "p:user_1288:user_5637",
    "seq": 0,
    "trace_id": "",
    "ts": 1785827569637,
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
| `ts` | `1785827569675` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `conv_id` | `p:user_7843:user_7971` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
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
      "conv_id": "p:user_7843:user_7971",
      "cursor": 0,
      "limit": 20
    },
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785827569675,
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
| `ts` | `1785827569676` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `has_more` | `false` |  |
| `messages` | `[{"burn_after_read":"false","burn_ttl_sec":0,"burned":"false","chat_type":"CHAT_PRIVATE","client_msg_id":"sm-8067","content":"\n\u000Bst-off-8035\u0010\u0001\u0018\u0001*\ntext/plain","conv_id":"p:user_7843:user_7971","conv_seq":1,"edit_version":0,"ext":{},"from":"user_7843","inbox_seq":1,"msg_id":"342927845493833728","msg_type":"MSG_STREAM","priority":"MSG_PRIORITY_NORMAL","recalled":"false","server_time":1785827569657,"target_users":[],"to":"user_7971"},{"burn_after_read":"false","burn_ttl_sec":0,"burned":"false","chat_type":"CHAT_PRIVATE","client_msg_id":"sm-6053","content":"\n\u000Bst-off-8035\u0010\u0002\u0018\u0002\"\u0003off*\ntext/plain","conv_id":"p:user_7843:user_7971","conv_seq":2,"edit_version":0,"ext":{},"from":"user_7843","inbox_seq":2,"msg_id":"342927845514805248","msg_type":"MSG_STREAM","priority":"MSG_PRIORITY_NORMAL","recalled":"false","server_time":1785827569663,"target_users":[],"to":"user_7971"},{"burn_after_read":"false","burn_ttl_sec":0,"burned":"false","chat_type":"CHAT_PRIVATE","client_msg_id":"sm-6085","content":"\n\u000Bst-off-8035\u0010\u0003\u0018\u0003*\ntext/plain","conv_id":"p:user_7843:user_7971","conv_seq":3,"edit_version":0,"ext":{},"from":"user_7843","inbox_seq":3,"msg_id":"342927845535776768","msg_type":"MSG_STREAM","priority":"MSG_PRIORITY_NORMAL","recalled":"false","server_time":1785827569668,"target_users":[],"to":"user_7971"}]` |  |
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
          "client_msg_id": "sm-8067",
          "content": "\n\u000Bst-off-8035\u0010\u0001\u0018\u0001*\ntext/plain",
          "conv_id": "p:user_7843:user_7971",
          "conv_seq": 1,
          "edit_version": 0,
          "ext": {},
          "from": "user_7843",
          "inbox_seq": 1,
          "msg_id": "342927845493833728",
          "msg_type": "MSG_STREAM",
          "priority": "MSG_PRIORITY_NORMAL",
          "recalled": "false",
          "server_time": 1785827569657,
          "target_users": [],
          "to": "user_7971"
        },
        {
          "burn_after_read": "false",
          "burn_ttl_sec": 0,
          "burned": "false",
          "chat_type": "CHAT_PRIVATE",
          "client_msg_id": "sm-6053",
          "content": "\n\u000Bst-off-8035\u0010\u0002\u0018\u0002\"\u0003off*\ntext/plain",
          "conv_id": "p:user_7843:user_7971",
          "conv_seq": 2,
          "edit_version": 0,
          "ext": {},
          "from": "user_7843",
          "inbox_seq": 2,
          "msg_id": "342927845514805248",
          "msg_type": "MSG_STREAM",
          "priority": "MSG_PRIORITY_NORMAL",
          "recalled": "false",
          "server_time": 1785827569663,
          "target_users": [],
          "to": "user_7971"
        },
        {
          "burn_after_read": "false",
          "burn_ttl_sec": 0,
          "burned": "false",
          "chat_type": "CHAT_PRIVATE",
          "client_msg_id": "sm-6085",
          "content": "\n\u000Bst-off-8035\u0010\u0003\u0018\u0003*\ntext/plain",
          "conv_id": "p:user_7843:user_7971",
          "conv_seq": 3,
          "edit_version": 0,
          "ext": {},
          "from": "user_7843",
          "inbox_seq": 3,
          "msg_id": "342927845535776768",
          "msg_type": "MSG_STREAM",
          "priority": "MSG_PRIORITY_NORMAL",
          "recalled": "false",
          "server_time": 1785827569668,
          "target_users": [],
          "to": "user_7971"
        }
      ],
      "next_cursor": 3
    },
    "route_key": "",
    "seq": 2,
    "trace_id": "",
    "ts": 1785827569676,
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
| `ts` | `1785827569648` | 发送时间戳（毫秒） |
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
    "payload_raw_bytes": 63,
    "route_key": "",
    "seq": 1,
    "trace_id": "",
    "ts": 1785827569648,
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
| `ts` | `1785827569648` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `action` | `stream_start` | 透传 action 名 |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `conv_id` | `` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `data` | `{"stream_id":"ps-5989"}` | 透传 JSON 字符串 |
| `from` | `user_7523` | 发送方 user_id |
| `persist` | `false` |  |
| `to` | `user_5925` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |
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
      "data": "{\"stream_id\":\"ps-5989\"}",
      "from": "user_7523",
      "persist": "false",
      "to": "user_5925",
      "ttl_sec": 0
    },
    "route_key": "",
    "seq": 0,
    "trace_id": "",
    "ts": 1785827569648,
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
| `ts` | `1785827569648` | 发送时间戳（毫秒） |
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
    "payload_raw_bytes": 76,
    "route_key": "",
    "seq": 4,
    "trace_id": "",
    "ts": 1785827569648,
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
| `ts` | `1785827569648` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `action` | `stream_chunk` | 透传 action 名 |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `conv_id` | `` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `data` | `{"chunk":"Hi","stream_id":"ps-5989"}` | 透传 JSON 字符串 |
| `from` | `user_7523` | 发送方 user_id |
| `persist` | `false` |  |
| `to` | `user_5925` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |
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
      "data": "{\"chunk\":\"Hi\",\"stream_id\":\"ps-5989\"}",
      "from": "user_7523",
      "persist": "false",
      "to": "user_5925",
      "ttl_sec": 0
    },
    "route_key": "",
    "seq": 0,
    "trace_id": "",
    "ts": 1785827569648,
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
| `ts` | `1785827569649` | 发送时间戳（毫秒） |
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
    "payload_raw_bytes": 61,
    "route_key": "",
    "seq": 7,
    "trace_id": "",
    "ts": 1785827569649,
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
| `ts` | `1785827569649` | 发送时间戳（毫秒） |
| `ver` | `1` | 协议版本，当前固定 1 |

**payload 字段**

| 字段 | E2E 实测值 | 说明 |
| --- | --- | --- |
| `action` | `stream_end` | 透传 action 名 |
| `chat_type` | `CHAT_PRIVATE` | 会话类型：CHAT_PRIVATE/CHAT_GROUP/CHAT_ROOM |
| `conv_id` | `` | 会话 ID；单聊 p:{lo}:{hi} 字典序 |
| `data` | `{"stream_id":"ps-5989"}` | 透传 JSON 字符串 |
| `from` | `user_7523` | 发送方 user_id |
| `persist` | `false` |  |
| `to` | `user_5925` | 接收目标：单聊=对端 uid；群=group_id；室=room_id |
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
      "data": "{\"stream_id\":\"ps-5989\"}",
      "from": "user_7523",
      "persist": "false",
      "to": "user_5925",
      "ttl_sec": 0
    },
    "route_key": "",
    "seq": 0,
    "trace_id": "",
    "ts": 1785827569649,
    "ver": 1
  },
  "step": 9
}
```

</details>
