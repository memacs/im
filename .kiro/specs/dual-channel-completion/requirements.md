# Requirements: 双通道收口

| 项 | 内容 |
| --- | --- |
| Spec | `dual-channel-completion` |
| 权威 | `docs/design/dual-channel-api.md` DD-031 |
| 状态 | 实施中 |

## Acceptance

1. `IM.Application.Dispatch` 覆盖全部客户端业务 cmd（好友/群/室/消息扩展/离线/透传/通道）。
2. REST §3.1 路径齐备，经 Dispatch → Services。
3. WS Commands 业务调用改经 Dispatch（PubSub 副作用仍可在 Command）。
4. ExUnit：各 REST 路径至少 1 条成功路径；全量 `mix test` 绿。
5. im_client / loadtest pending 项完成（除环境实测；P7-08/P8-09 已 done）。
