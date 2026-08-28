# 流式消息 - Elixir 实现

| 项 | 内容 |
|------|------|
| 语言 | Elixir |
| 设计文档 | [stream-message.md](../../design/stream-message.md) |
| Roadmap | Phase 7：P7-07（透传模式）；P7-08（消息模式，**done**） |

> **文档分级**：边缘模块 impl。透传见设计文档；消息模式见 `.kiro/specs/p7-08-p8-09/`。

> `MSG_STREAM`：`content` 为 `StreamContent` protobuf 字节，每块独立落库；`IM.Services.StreamManager` 校验序号与生命周期；`Offline.pull` 还原 `msg_type`。

---

## 1. 流状态管理

```elixir
defmodule IM.Services.StreamManager do
  use GenServer
  
  # 流状态: %{stream_id => %{status, chunks, sequence, ...}}
  
  def start_stream(stream_id, metadata) do
    GenServer.call(__MODULE__, {:start, stream_id, metadata})
  end
  
  def append_chunk(stream_id, chunk) do
    GenServer.cast(__MODULE__, {:append, stream_id, chunk})
  end
  
  def end_stream(stream_id) do
    GenServer.call(__MODULE__, {:end, stream_id})
  end
  
  # ...
end
```

---

## 2. 顺序保证

```elixir
# 使用 sequence 字段排序
def get_full_text(stream_id) do
  chunks = get_chunks(stream_id)
  chunks
  |> Enum.sort_by(& &1.sequence)
  |> Enum.map(& &1.chunk)
  |> Enum.join()
end
```

---

## 3. 错误处理

```elixir
def handle_stream_error(stream_id, error) do
  # 1. 推送错误通知
  push_stream_error(stream_id, error)
  
  # 2. 清理流状态
  cleanup_stream(stream_id)
  
  # 3. 记录日志
  Logger.error("Stream error: #{stream_id}, #{inspect(error)}")
end
```

---

## 4. 流 ID 生成

```elixir
def generate_stream_id do
  UUID.uuid4()
end
```

---

## 5. 权限校验

```elixir
def validate_stream_access(user_id, stream_id, conv_id) do
  # 检查用户是否有权限访问该会话
  with :ok <- check_conversation_access(user_id, conv_id),
       :ok <- check_stream_owner(user_id, stream_id) do
    :ok
  end
end
```

