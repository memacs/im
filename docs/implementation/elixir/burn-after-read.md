# 阅后即焚 - Elixir 实现

| 项 | 内容 |
|------|------|
| 语言 | Elixir |
| 设计文档 | [burn-after-read.md](../../design/burn-after-read.md) |
| Roadmap | Phase 7（P7-09）；依赖 P7-02（已读回执） |

> **文档分级**：边缘模块 impl。行为规范见设计文档；本文仅列模块与测试要点。

---

## 1. 模块

| 模块 | 职责 |
|------|------|
| `IM.Services.Message.Send` | `CMD_MSG_SEND` 校验 `burn_after_read`（租户开关、仅单聊、`burn_ttl_sec` 上限） |
| `IM.Services.Message.Read` | `CMD_MSG_READ` 后调用 `BurnScheduler.schedule/2` |
| `IM.Services.Message.Burn` | 销毁逻辑：清空 content、`burned=true`、取消与撤回协调 |
| `IM.Jobs.MessageBurn` | Oban 延迟执行；幂等 `msg_id` |
| `IM.Delivery.Router` | `CMD_MSG_BURN_PUSH` 扇出双方全设备 |

---

## 2. 发送校验

```elixir
defmodule IM.Services.Message.Send do
  def validate_burn!(message, app_config) do
    if message.burn_after_read do
      cond do
        not app_config.burn_after_read_enabled ->
          {:error, :CODE_MSG_BURN_DENIED}

        message.chat_type != :CHAT_PRIVATE ->
          {:error, :CODE_MSG_BURN_DENIED}

        burn_ttl(message) > app_config.burn_ttl_sec_max ->
          {:error, :CODE_MSG_BURN_DENIED}

        true ->
          :ok
      end
    else
      :ok
    end
  end

  defp burn_ttl(%{burn_ttl_sec: 0}), do: 0
  defp burn_ttl(%{burn_ttl_sec: sec}) when sec > 0, do: sec
  defp burn_ttl(_), do: :default_from_app_config
end
```

---

## 3. 已读触发销毁

```elixir
defmodule IM.Services.Message.BurnScheduler do
  @doc """
  接收方 CMD_MSG_READ 且 conv_seq 覆盖阅后即焚消息时调度 Job。
  """
  def on_read(%MsgRead{} = read, ctx) do
    MessageStore.list_burn_pending_in_conv(read.conv_id, up_to: read.conv_seq)
    |> Enum.reject(&(&1.from == read.from))
    |> Enum.each(&schedule_burn/1)
  end

  defp schedule_burn(msg) do
    delay = msg.burn_ttl_sec

    %{msg_id: msg.msg_id, app_key: msg.app_key}
  |> IM.Jobs.MessageBurn.new(schedule_in: delay)
  |> Oban.insert()
  end
end
```

---

## 4. 销毁执行

```elixir
defmodule IM.Jobs.MessageBurn do
  use Oban.Worker, queue: :message_burn, unique: [period: 300, keys: [:msg_id]]

  @impl Oban.Worker
  def perform(%{args: %{"msg_id" => msg_id, "app_key" => app_key}}) do
    with {:ok, msg} <- MessageStore.get(msg_id, app_key),
         false <- msg.burned or msg.recalled,
         {:ok, burned} <- MessageStore.mark_burned(msg) do
      Delivery.Router.push_burn(burned)
      :ok
    else
      {:error, :not_found} -> :ok
      true -> :ok
    end
  end
end
```

- `mark_burned`：`content = ""`，`burned = true`，刷新 `updated_at`
- 撤回成功时 `Recall` 须 `Oban.cancel` 同 `msg_id` 的 pending `MessageBurn`

---

## 5. 配置（`app_configs`）

| 键 | 默认 |
|----|------|
| `burn_after_read_enabled` | `true` |
| `burn_ttl_sec_default` | `0` |
| `burn_ttl_sec_max` | `3600` |

环境变量 `IM_BURN_AFTER_READ_ENABLED=false` 可作全站紧急关闭（与 `FanoutPolicy` 全局 Flag 模式一致）。

---

## 6. 验收要点

- 单聊发送 `burn_after_read=true` → PUSH 带标志 → 对端 READ → 双方收 `BURN_PUSH` → 本地不可再看正文
- `burn_ttl_sec=30` → READ 后约 30s 销毁
- 群聊 / 聊天室带 burn 标志 → `CODE_MSG_BURN_DENIED`（2006）
- 租户 `burn_after_read_enabled=false` → 拒绝发送
- 销毁前 `OFFLINE_PULL` 有正文；销毁后有 `burned=true` 墓碑
- 时间窗内 `RECALL` 成功 → 不执行 Burn；已 `burned` 后 `RECALL` 拒绝
- `burn_after_read` 消息 `EDIT` 拒绝

---
