# Design: Phase 8

## 组件

| 模块 | 职责 |
| --- | --- |
| `IM.Services.Group` | 群 CRUD、成员、角色、PUSH 载荷组装 |
| `IM.Stores.GroupStore` | groups/group_members；DB role：0 成员 / 1 管理 / 2 群主 |
| `IM.WebSocket.Commands.Group.*` | 一 cmd 一模块；CREATE→RESP，其余→PUSH+广播 |
| `IM.Services.Room` / `Commands.Room*` | 补齐 DISMISS/KICK/UPDATE + 成员广播 |
| `IM.Services.Friend` / `FriendStore` | friendships + friend_requests；拉黑拦截 MSG_SEND |

## 角色映射

| DB | Proto `GroupMemberRole` |
| --- | --- |
| 0 | MEMBER (1) |
| 1 | ADMIN (2) |
| 2 | OWNER (3) |

## 推送模式

同撤回：操作者 `Reply.ok(..., PUSH, seq)`；广播 `Push.build` + `Delivery.Router.push_packet`（`seq=0`）。

## 测试策略

- Service/DataCase：建群、踢人权限、转让、解散
- 不强制全链路 WS；Router 注册冒烟可附带
