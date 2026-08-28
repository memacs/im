# 多端同步 - Elixir 实现

| 项 | 内容 |
|------|------|
| 语言 | Elixir |
| 设计文档 | [multi-device.md](../../design/multi-device.md) |
| 设备限额 | [auth.md](../../design/auth.md) §8 → [auth.md](auth.md) §5 |
| Roadmap | Phase 3+（`recipients` 含发送方其他设备） |

> **文档分级**：边缘模块 impl。行为规范见设计文档；本文仅列模块与测试要点。

---

## 1. 发送方多设备同步

```elixir
def push_to_sender_other_devices(app_key, from_uid, from_device_id, message) do
  # 获取发送方所有在线设备
  devices = UserLocator.find_devices(app_key, from_uid)
  
  # 排除发送设备
  other_devices = Enum.reject(devices, fn {device_id, _} -> 
    device_id == from_device_id 
  end)
  
  # 推送给其他设备
  Enum.each(other_devices, fn {_device_id, target} ->
    deliver(target, encode_push_packet(message))
  end)
end
```

---

## 2. 已读状态同步

```elixir
def handle_msg_read(app_key, from_uid, from_device_id, msg_read) do
  # 1. 持久化已读位点
  update_read_cursor(app_key, from_uid, msg_read.conv_id, msg_read.conv_seq)
  
  # 2. 推送给对端（单聊）
  if msg_read.chat_type == :CHAT_PRIVATE do
    push_read_receipt_to_peer(app_key, msg_read)
  end
  
  # 3. 推送给自己的其他设备
  push_read_receipt_to_other_devices(app_key, from_uid, from_device_id, msg_read)
end
```

---

## 3. 按平台设备数限制

在 `CMD_AUTH_REQ` 成功校验 token 后、返回 `AUTH_RESP` 前调用 `IM.Services.DeviceLimit.enforce/4`（见 [auth.md](auth.md) §5）。

Tracker 元数据须含 `platform`，供按平台统计在线 `device_id`：

```elixir
IM.UserTracker.track(socket, app_key, user_id, %{
  device_id: device_id,
  platform: normalize_platform(platform),
  connected_at: System.system_time(:millisecond)
})
```

配置读取：

```elixir
IM.AppConfig.get_json(app_key, "device", "max_devices_per_platform")
IM.AppConfig.get_string(app_key, "device", "device_limit_policy", "kick_oldest_on_platform")
```

---
