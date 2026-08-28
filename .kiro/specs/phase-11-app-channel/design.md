# Design: Phase 11 App Channel

## 组件

| 模块 | 职责 |
| --- | --- |
| `IM.Services.Channel` | 订阅/取消、上行、下行业务入口 |
| `IM.Channel.ACL` | channel_id 格式 + 默认/配置权限 |
| `IM.Channel.RateLimiter` | 连接 1/s burst 2 + Channel 聚合 |
| `IM.Delivery.ChannelRouter` | PubSub topic / subscribe / broadcast |
| `IM.EventBus.AppEvents` | `im.app_events` 旁路 |
| `IM.WebSocket.Commands.Channel.*` | 900–905 薄适配 |
| `IMWeb.Internal.V1.ChannelController` | 下行 publish |
| `IMWeb.Api.V1.ChannelController` | REST 对等 |

## 扇出

`encode` 一次 → `PubSub.broadcast({:channel_push, bin})` → PacketTransport `handle_info` 写出。**禁止** GroupPusher。

## 测试

- RateLimiter / ACL / Service 单元
- PubSub：subscribe + publish_down 收帧
- EventBus Buffer：启用后 snapshot 含 `:app_events`
