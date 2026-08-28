# Packet.payload 压缩 - Elixir 实现

| 项 | 内容 |
|------|------|
| 语言 | Elixir |
| 设计文档 | [payload-compression.md](../../design/payload-compression.md) |
| Roadmap | Phase 2（P2-03 鉴权字段透传）；算法 Phase 9+ 可选 |

> **v1**：`AuthResp.payload_compression` 固定 `NONE`；`Packet.compression` 解析但不解压。

---

## 1. 模块落位

| 模块 | 职责 |
|------|------|
| `IM.Protocol.Codec` | 读 `Packet.compression`；NONE 直解；GZIP/LZ4 预留 `decompress/2` |
| `IM.WebSocket.Commands.Auth` | 协商 `compression_offered` → `payload_compression` |
| `IM.Services.Session` | HTTP `config.payload_compression` 与 WS 对齐 |

---

## 2. 协商（示意）

```elixir
@default_offered [:none]

def negotiate_compression(offered, app_key) do
  client = normalize_offered(offered)
  server = allowed_for_app(app_key) # v1: [:none]
  chosen = Enum.find(client, &(&1 in server)) || :none
  {:ok, chosen}
end
```

---

## 3. 验收要点

- 空 `compression_offered` → `AuthResp.payload_compression = NONE`
- `AUTH_REQ` / `AUTH_RESP` 的 payload 不压缩
- 未知枚举值 → `CMD_ERROR` 或按 `NONE` 处理（实现时二选一并写进 protocol 测试）
