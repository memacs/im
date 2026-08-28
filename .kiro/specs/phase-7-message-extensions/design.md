# Design: Phase 7

| Service | Commands |
|---------|----------|
| `Message.ack_batch_up` | MsgAckBatch |
| `MessageRead.mark` | MsgRead |
| `MessageRecall.recall` | MsgRecall |
| `MessageEdit.edit` | MsgEdit |
| `Passthrough.send` | Passthrough |
| `IM.Jobs.MessageBurn` | via Read |
| `IM.Jobs.*TtlPurge` | scheduled GenServer（Oban 延后） |

Burn / TTL 不用 Oban：`Process.send_after` + `IM.Jobs.TtlPurge` 周期任务。
