# Tasks: Phase 2 连接生命周期

| 项 | 内容 |
| --- | --- |
| Spec | `phase-2-connection-lifecycle` |
| Roadmap | P2-01 ~ P2-13 |
| 状态 | **已完成**（`mix test`）；Release+K8s 黄金路径建议部署后冒烟 |

- [x] **1. P2-10 Dispatch** — cmd → Services 注册表（auth/heartbeat/session 相关）
- [x] **2. P2-12 Migration + Stores + Session** — users/user_devices/access_tokens；HTTP 登录签发
- [x] **3. P2-11 REST pipeline** — TraceId、Bearer、Fallback、Session/Device controllers
- [x] **4. P2-04 Auth Behaviour + Services.Auth** — token 校验可测
- [x] **5. P2-01/02 PacketTransport + ConnectionState** — 二进制 WS、状态机、超时
- [x] **6. P2-03/05 Commands Auth/Heartbeat** — AUTH_RESP、心跳、空闲重置
- [x] **7. P2-07 Registry** — 按 user_id/device_id 查 pid
- [x] **8. P2-07b DeviceLimit** — 超限 reject / kick_oldest
- [x] **9. P2-06/13 Kick + DeviceBan + clear_local_data ACK**
- [x] **10. P2-08/09 Telemetry + IM.Log MVP**
- [x] **11. 收尾** — `PGPORT=15432 mise run test` 绿；PROGRESS / 本文件勾选
