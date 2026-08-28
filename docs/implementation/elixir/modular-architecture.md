# 模块化实现架构 - Elixir 实现

| 项 | 内容 |
|------|------|
| 语言 | Elixir |
| 设计文档 | [modular-architecture.md](../../design/modular-architecture.md) |

---

## 1. 模块划分

### 1.1 服务层模块

#### SingleChat（单聊）

```elixir
defmodule IM.Services.SingleChat do
  @moduledoc """
  单聊业务模块。
  
  职责：
  - 验证单聊逻辑
  - 确定推送目标（对端 + 发送方其他设备，写扩散 2 行 `user_inbox`）
  - 落库与群聊共用 `message_bodies` + `user_inbox`（见 database-design §3）
  - 不负责：如何推送、如何编码
  """
  
  alias IM.Domain.{Message, User}
  
  @doc """
  发送单聊消息。
  
  返回：
  - {:ok, message, recipients} - 成功，返回消息和推送目标列表
  - {:error, reason} - 失败
  """
  def send(message, context) do
    with :ok <- validate_single_chat(message),
         {:ok, recipients} <- determine_recipients(message) do
      {:ok, message, recipients}
    end
  end
  
  defp validate_single_chat(%{from: from, to: to}) when from == to do
    {:error, :cannot_send_to_self}
  end
  
  defp validate_single_chat(%{from: _from, to: to}) do
    if User.exists?(to) do
      :ok
    else
      {:error, :user_not_found}
    end
  end
  
  defp determine_recipients(%{from: from, to: to}) do
    # 推送目标：对端 + 自己的其他设备
    recipients = [
      {:user, to},           # 对端
      {:user_other, from}    # 自己的其他设备（排除发送设备）
    ]
    {:ok, recipients}
  end
end
```

#### GroupChat（群聊）

```elixir
defmodule IM.Services.GroupChat do
  @moduledoc """
  群聊业务模块。
  
  职责：
  - 群成员查询
  - 确定推送目标
  - 群聊写扩散：`message_bodies` 1 行 + `user_inbox` 瘦行/成员（与单聊同模型，行数为 N）
  """
  
  alias IM.Domain.{Message, Group}
  
  @doc """
  发送群聊消息。
  
  返回：
  - {:ok, message, recipients} - 成功
  - {:error, reason} - 失败
  """
  def send(message, context) do
    with {:ok, group} <- validate_group(message),
         {:ok, members} <- get_group_members(group),
         {:ok, recipients} <- determine_recipients(message, members) do
      {:ok, message, recipients}
    end
  end
  
  defp validate_group(%{to: group_id}) do
    case Group.get(group_id) do
      nil -> {:error, :group_not_found}
      group -> {:ok, group}
    end
  end
  
  defp get_group_members(group) do
    members = Group.get_members(group.id)
    {:ok, members}
  end
  
  defp determine_recipients(%{from: from}, members) do
    # 推送目标：所有群成员 + 自己的其他设备（在线过滤在推送层完成）
    recipients = Enum.map(members, fn member_id ->
      if member_id == from do
        {:user_other, from}  # 自己的其他设备
      else
        {:user, member_id}
      end
    end)
    {:ok, recipients}
  end
end
```

#### RoomChat（聊天室）

```elixir
defmodule IM.Services.RoomChat do
  @moduledoc """
  聊天室业务模块。
  
  职责：
  - 聊天室成员管理
  - 确定推送目标（仅在线成员）
  - PubSub 广播
  """
  
  alias IM.Domain.Room
  
  @doc """
  发送聊天室消息。
  
  返回：
  - {:ok, message, recipients} - 成功
  - {:error, reason} - 失败
  """
  def send(message, context) do
    with {:ok, room} <- validate_room(message),
         {:ok, recipients} <- determine_recipients(room) do
      {:ok, message, recipients}
    end
  end
  
  defp validate_room(%{to: room_id}) do
    case Room.get(room_id) do
      nil -> {:error, :room_not_found}
      room -> {:ok, room}
    end
  end
  
  defp determine_recipients(room) do
    # 聊天室只推送给在线成员
    online_members = Room.get_online_members(room.id)
    recipients = Enum.map(online_members, fn {user_id, device_ids} ->
      {:devices, user_id, device_ids}
    end)
    {:ok, recipients}
  end
end
```

---

## 2. 推送层模块

### 2.1 Router（通用推送模块）

```elixir
defmodule IM.Delivery.Router do
  @moduledoc """
  通用推送路由模块。
  
  职责：
  - 解析 recipients 列表
  - 定位用户设备（本地/远程）
  - 编码 Packet
  - 推送消息
  
  不负责：
  - 决定推送给谁（由业务层决定）
  - 消息存储（由存储层决定）
  """
  
  alias IM.Delivery.{Encoder, ConnectionManager}
  
  @type recipient :: 
    {:user, user_id :: String.t()} |
    {:user_other, user_id :: String.t()} |
    {:devices, user_id :: String.t(), device_ids :: [String.t()]} |
    {:device, user_id :: String.t(), device_id :: String.t()}
  
  @doc """
  推送消息给指定的 recipients。
  
  参数：
  - message: 要推送的消息
  - recipients: 推送目标列表
  - opts: 选项
    - exclude: 排除的设备 {user_id, device_id}
    - encode_once: 是否只编码一次（优化）
  
  返回：
  - {:ok, pushed_count} - 成功，返回推送设备数
  - {:error, reason} - 失败
  """
  @spec push(message :: map(), recipients :: [recipient()], opts :: keyword()) ::
    {:ok, non_neg_integer()} | {:error, term()}
  def push(message, recipients, opts \\ []) do
    exclude = Keyword.get(opts, :exclude)
    encode_once = Keyword.get(opts, :encode_once, true)
    
    # 1. 编码 Packet（只编码一次，优化性能）
    encoded_packet = if encode_once do
      Encoder.encode_push_packet(message)
    else
      nil
    end
    
    # 2. 解析 recipients，获取目标设备
    {:ok, targets} = resolve_targets(recipients, exclude)
    
    # 3. 推送到每个目标
    pushed_count = do_push(targets, message, encoded_packet)
    
    {:ok, pushed_count}
  end
  
  defp resolve_targets(recipients, exclude) do
    targets = Enum.flat_map(recipients, fn recipient ->
      case recipient do
        {:user, user_id} ->
          # 查找该用户的所有设备
          ConnectionManager.find_devices(user_id)
        
        {:user_other, user_id} ->
          # 查找该用户的其他设备（排除 exclude）
          ConnectionManager.find_devices(user_id)
          |> filter_exclude(exclude)
        
        {:devices, user_id, device_ids} ->
          # 指定的设备列表
          Enum.map(device_ids, fn device_id ->
            {user_id, device_id}
          end)
        
        {:device, user_id, device_id} ->
          # 单个设备
          [{user_id, device_id}]
      end
    end)
    
    {:ok, targets}
  end
  
  defp filter_exclude(targets, nil), do: targets
  defp filter_exclude(targets, {exclude_user_id, exclude_device_id}) do
    Enum.reject(targets, fn {user_id, device_id} ->
      user_id == exclude_user_id and device_id == exclude_device_id
    end)
  end
  
  defp do_push(targets, message, pre_encoded) do
    encoded = pre_encoded || Encoder.encode_push_packet(message)
    
    Enum.reduce(targets, 0, fn {user_id, device_id}, count ->
      case ConnectionManager.deliver(user_id, device_id, encoded) do
        :ok -> count + 1
        {:error, _} -> count
      end
    end)
  end
end
```

### 2.2 Encoder（编码模块）

```elixir
defmodule IM.Delivery.Encoder do
  @moduledoc """
  Packet 编码模块。
  
  职责：
  - 编码各种类型的 Packet
  - 提供编码缓存（可选）
  """
  
  alias IM.Protocol.{Packet, Codec}
  
  @doc """
  编码消息推送 Packet。
  """
  def encode_push_packet(message) do
    %Packet{
      ver: 1,
      cmd: :CMD_MSG_PUSH,
      seq: 0,
      ts: System.system_time(:millisecond),
      trace_id: message.trace_id,
      payload: encode_message(message)
    }
    |> Codec.encode()
  end
  
  @doc """
  编码批量推送 Packet。
  """
  def encode_push_batch_packet(messages) do
    %Packet{
      ver: 1,
      cmd: :CMD_MSG_PUSH_BATCH,
      seq: 0,
      ts: System.system_time(:millisecond),
      payload: encode_messages_batch(messages)
    }
    |> Codec.encode()
  end
  
  defp encode_message(message), do: message
  defp encode_messages_batch(messages), do: messages
end
```

### 2.3 ConnectionManager（连接管理模块）

```elixir
defmodule IM.Delivery.ConnectionManager do
  @moduledoc """
  连接管理模块。
  
  职责：
  - 查找用户在线设备
  - 推送消息到设备
  """
  
  alias IM.Presence.Tracker
  
  @doc """
  查找用户的所有在线设备。
  
  返回：
  - [{user_id, device_id}] - 设备列表
  """
  def find_devices(user_id) do
    Tracker.find_devices(user_id)
  end
  
  @doc """
  推送消息到指定设备。
  """
  def deliver(user_id, device_id, encoded_packet) do
    case Tracker.find_device(user_id, device_id) do
      {:local, pid} ->
        send(pid, {:push_binary, encoded_packet})
        :ok
      
      {:remote, node, pid} ->
        :erlang.send({pid, node}, {:push_binary, encoded_packet})
        :ok
      
      :not_found ->
        {:error, :device_offline}
    end
  end
end
```

---

## 3. 组合使用

### 3.1 消息发送服务

```elixir
defmodule IM.Services.Message do
  @moduledoc """
  消息发送服务 - 组合业务层和推送层。
  """
  
  alias IM.Services.{SingleChat, GroupChat, RoomChat}
  alias IM.Delivery.Router
  alias IM.Storage.MessageStore
  
  @doc """
  发送消息 - 统一入口。
  """
  def send_message(message, context) do
    with {:ok, message, recipients} <- dispatch_by_chat_type(message, context),
         {:ok, message} <- save_message(message, context),
         {:ok, _count} <- push_message(message, recipients, context) do
      {:ok, message.msg_id}
    end
  end
  
  # 根据会话类型分发到不同的业务模块
  defp dispatch_by_chat_type(%{chat_type: :CHAT_PRIVATE} = message, context) do
    SingleChat.send(message, context)
  end
  
  defp dispatch_by_chat_type(%{chat_type: :CHAT_GROUP} = message, context) do
    GroupChat.send(message, context)
  end
  
  defp dispatch_by_chat_type(%{chat_type: :CHAT_ROOM} = message, context) do
    RoomChat.send(message, context)
  end
  
  # 存储消息
  defp save_message(message, context) do
    MessageStore.save(message, context)
  end
  
  # 推送消息 - 复用 Router
  defp push_message(message, recipients, context) do
    Router.push(message, recipients,
      exclude: {context.device.device_id},
      encode_once: true
    )
  end
end
```

---

## 4. 多端同步模块

```elixir
defmodule IM.Services.MultiDeviceSync do
  @moduledoc """
  多端同步模块 - 独立模块，可复用。
  
  职责：
  - 将消息同步给发送者的其他设备
  - 可被任何业务场景复用（单聊、群聊、聊天室等）
  
  独立性：
  - 不关心消息类型
  - 不关心会话类型
  - 只负责同步给发送者的其他设备
  """
  
  alias IM.Core.Delivery
  
  @doc """
  同步消息给发送者的其他设备。
  """
  @spec sync_to_other_devices(message :: map(), from_user_id :: String.t(), exclude_device_id :: String.t()) ::
    {:ok, map()} | {:error, term()}
  def sync_to_other_devices(message, from_user_id, exclude_device_id) do
    user_list = [
      {from_user_id, :other}  # 发送者的其他设备
    ]
    
    Delivery.deliver(message, user_list,
      exclude: {from_user_id, exclude_device_id}
    )
  end
end
```

---

## 5. Hook 模块

### 5.1 Hook 行为定义

```elixir
defmodule IM.Hooks.Behaviour do
  @moduledoc """
  Hook 行为定义 - 所有 Hook 都遵循此接口。
  """
  
  @callback pre_send(message :: map(), context :: map()) ::
    {:ok, message :: map()} | {:error, term()} | {:reject, term()}
  
  @callback post_send(message :: map(), context :: map()) :: :ok
  
  @callback pre_push(message :: map(), context :: map()) ::
    {:ok, message :: map()} | {:skip, term()}
  
  @callback post_push(message :: map(), context :: map()) :: :ok
end
```

### 5.2 Hook Pipeline 实现

```elixir
defmodule IM.Hooks.Pipeline do
  @moduledoc """
  Hook 流水线 - 独立模块，管理所有 Hook 的执行。
  """
  
  use GenServer
  
  defstruct [
    :pre_send_hooks,
    :post_send_hooks,
    :pre_push_hooks,
    :post_push_hooks
  ]
  
  def run_pre_send(message, context) do
    hooks = get_hooks(:pre_send)
    
    Enum.reduce_while(hooks, {:ok, message}, fn hook, {:ok, msg} ->
      try do
        case hook.pre_send(msg, context) do
          {:ok, new_msg} -> {:cont, {:ok, new_msg}}
          {:error, reason} -> {:halt, {:error, reason}}
          {:reject, reason} -> {:halt, {:reject, reason}}
        end
      rescue
        error ->
          Logger.error("Hook #{hook} failed: #{inspect(error)}")
          {:halt, {:error, :hook_failed}}
      end
    end)
  end
  
  def run_post_send(message, context) do
    hooks = get_hooks(:post_send)
    
    Task.start(fn ->
      Enum.each(hooks, fn hook ->
        try do
          hook.post_send(message, context)
        rescue
          error ->
            Logger.error("Hook #{hook} failed: #{inspect(error)}")
        end
      end)
    end)
    
    :ok
  end
  
  defp get_hooks(type) do
    GenServer.call(__MODULE__, {:get_hooks, type})
  end
end
```

### 5.3 Hook 配置

```elixir
# config/config.exs
config :im, IM.Hooks.Pipeline,
  pre_send: [
    IM.Hooks.RiskControl,      # 风控检查（先执行）
    IM.Hooks.ContentFilter     # 敏感词过滤（后执行）
  ],
  post_send: [
    IM.Hooks.AuditLog          # 审计日志
  ],
  pre_push: [],
  post_push: [
    IM.Hooks.AuditLog          # 推送日志
  ]
```

---

## 6. 投递接口

```elixir
defmodule IM.Core.Delivery do
  @moduledoc """
  IM Core 投递接口 - 核心接口，支持服务拆分。
  """
  
  @doc """
  投递消息给指定的用户列表。
  
  ## 参数
  
  - message: 要投递的消息（已构造完成）
  - user_list: 目标用户列表 [{user_id, device_ids}]
  - opts: 选项
    - exclude: 排除的设备 {user_id, device_id}
    - ack_to: ACK 回传地址（可选）
    - trace_id: 链路追踪 ID
  
  ## user_list 格式
  
  - {user_id, :all} - 该用户的所有设备
  - {user_id, :other} - 该用户的其他设备（需配合 exclude）
  - {user_id, [device_ids]} - 指定的设备列表
  """
  @spec deliver(message :: map(), user_list :: list(), opts :: keyword()) ::
    {:ok, map()} | {:error, term()}
  def deliver(message, user_list, opts \\ []) do
    # 实现见上文 Router
  end
end
```

---

## 7. 性能优化

### 7.1 Packet 编码优化

```elixir
# 优化：只编码一次，推送给多个设备
def push_optimized(message, recipients) do
  encoded = Encoder.encode_push_packet(message)
  
  Enum.each(recipients, fn recipient ->
    Router.push_encoded(encoded, recipient)
  end)
end
```

### 7.2 大群推送优化

```elixir
# 大群推送：树状扇出 + 批量推送
def push_large_group(message, recipients, opts) when length(recipients) > 500 do
  # 1. 按节点分组
  by_node = group_by_node(recipients)
  
  # 2. 每个节点批量推送
  Enum.each(by_node, fn {node, targets} ->
    push_to_node_batch(node, message, targets)
  end)
end
```

