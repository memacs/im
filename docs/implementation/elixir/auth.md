# 连接与鉴权 - Elixir 实现

| 项 | 内容 |
|------|------|
| 语言 | Elixir |
| 设计文档 | [auth.md](../../design/auth.md) §7、§9 |
| Roadmap | Phase 2（P2-02 ~ P2-06） |

---

## 1. 模块划分

| 模块 | 职责 |
|------|------|
| `IMWeb.UserSocket` | WebSocket 建连、二进制帧收发 |
| `IM.WebSocket.ConnectionState` | **连接状态机**（唯一入口校验） |
| `IM.WebSocket.Handler` | 解码后分发到各 `Commands.*` |
| `IM.WebSocket.Commands.Auth` | `CMD_AUTH_REQ` / `CMD_AUTH_RESP` |
| `IM.WebSocket.Commands.Kick` | `CMD_KICK` 推送 |
| `IM.Services.DeviceLimit` | 按平台在线设备数检查与 enforcement |
| `IM.Connection.Registry` | 本节点 `device_id → pid` 映射 |

认证逻辑委托给 [`IM.Auth`](auth-module.md) / `IM.Services.Session`；**状态合法性**由 `ConnectionState` 负责。

### 客户端建连（摘要）

见 [auth.md](../../design/auth.md) §9：`POST /api/v1/sessions` → 缓存 token → WS `AUTH_REQ`；失败回 HTTP；封禁走 `IM.Services.DeviceBan`。

---

## 2. 连接状态机

### 2.1 状态

```elixir
defmodule IM.WebSocket.ConnectionState do
  @type t :: :unauthenticated | :authenticated | :closing

  @auth_timeout_ms 10_000
end
```

| 状态 | 进入条件 |
|------|----------|
| `:unauthenticated` | `mount` / `connect` 成功 |
| `:authenticated` | `AUTH_RESP` 成功 |
| `:closing` | 任意非法转移、KICK、空闲超时、对端关闭 |

### 2.2 允许矩阵（硬约束）

```elixir
@unauthenticated_only [:CMD_AUTH_REQ]

@authenticated_cmds [
  :CMD_HEARTBEAT_REQ,
  :CMD_MSG_SEND,
  :CMD_MSG_ACK_UP,
  :CMD_MSG_ACK_BATCH_UP,
  :CMD_MSG_READ,
  :CMD_OFFLINE_PULL_REQ,
  :CMD_MSG_RECALL_REQ,
  :CMD_MSG_EDIT_REQ,
  :CMD_PASSTHROUGH
  # + GROUP_* / ROOM_* / FRIEND_* 等已注册 cmd
]

def allow?(:unauthenticated, :CMD_AUTH_REQ), do: :ok
def allow?(:unauthenticated, _cmd), do: {:error, :silent_close}

def allow?(:authenticated, :CMD_AUTH_REQ), do: {:error, :already_authenticated}
def allow?(:authenticated, cmd) when cmd in @authenticated_cmds, do: :ok
def allow?(:authenticated, cmd) when is_group_cmd(cmd), do: :ok
def allow?(:authenticated, cmd) when is_room_cmd(cmd), do: :ok
def allow?(:authenticated, cmd) when is_friend_cmd(cmd), do: :ok
def allow?(:authenticated, _cmd), do: {:error, :invalid_cmd}

def allow?(:closing, _cmd), do: {:error, :silent_close}
```

**已鉴权禁止再次 `AUTH_REQ`** — 必须断开，不得当作幂等成功。

### 2.3 统一入口

```elixir
defmodule IMWeb.UserSocket do
  def handle_in({:binary, data}, socket) do
    with {:ok, packet} <- IM.Protocol.Codec.decode(data),
         :ok <- ConnectionState.allow!(socket.assigns.state, packet.cmd) do
      IM.WebSocket.Handler.dispatch(packet, socket)
    else
      {:error, :silent_close} ->
        {:stop, :state_violation, socket}

      {:error, :already_authenticated} ->
        reply_error_and_close(packet, socket, 1001, "already_authenticated")

      {:error, :invalid_cmd} ->
        reply_error_and_close(packet, socket, 2001, "invalid_cmd_in_state")

      {:error, _} = err ->
        err
    end
  end
end
```

### 2.4 状态转移

```elixir
def on_auth_success(socket, ctx) do
  cancel_auth_timeout(socket)

  socket
  |> assign(state: :authenticated)
  |> assign(:app_key, ctx.app_key)
  |> assign(:user_id, ctx.user_id)
  |> assign(:device_id, ctx.device_id)
  |> assign(:session_id, ctx.session_id)
  |> assign(:platform, ctx.platform)
end

def begin_close(socket, reason) do
  assign(socket, state: :closing, close_reason: reason)
end
```

- 未鉴权超时：`:silent_close`，不发 `CMD_ERROR`
- 鉴权失败：`CMD_ERROR` + `CODE_UNAUTHORIZED` → `closing` → `stop`
- 重复 `AUTH`：`CMD_ERROR` + `already_authenticated` → `closing`

---

## 3. Auth Handler

```elixir
defmodule IM.WebSocket.Commands.Auth do
  def handle(packet, %{assigns: %{state: :unauthenticated}} = socket) do
    case IM.Auth.Manager.authenticate(decode(packet), socket) do
      {:ok, ctx} ->
        socket = ConnectionState.on_auth_success(socket, ctx)
        IM.EventBus.Session.login(ctx)
        {:reply, auth_resp(packet, ctx), socket}

      {:error, :device_limit_exceeded} ->
        {:stop, :device_limit, reply_device_limit(packet, socket)}

      {:error, reason} ->
        {:stop, {:auth_failed, reason}, reply_unauthorized(packet, socket)}
    end
  end

  # 不应到达：ConnectionState 已在入口拦截
  def handle(_packet, %{assigns: %{state: :authenticated}}) do
    {:stop, :already_authenticated, socket}
  end
end
```

---

## 4. 鉴权成功后上下文

`authenticated` 后 `assigns` 含 `app_key` / `user_id` / `device_id` / `session_id` / `platform`。业务 Handler **禁止**信任 payload 中的 `from`。

---

## 5. 设备限额与互踢

鉴权成功路径（`on_auth_success` 之前）：

```elixir
defmodule IM.Services.DeviceLimit do
  @moduledoc """
  按 platform 限制在线 device_id 数。配置见 app_configs category=device。
  设计：docs/design/auth.md §8
  """

  @type policy :: :reject | :kick_oldest_on_platform

  @spec enforce(app_key(), user_id(), device_id(), platform(), keyword()) ::
          :ok | {:error, :device_limit_exceeded} | {:kick, [Device.t()]}

  def enforce(app_key, user_id, device_id, platform, opts \\ []) do
    # 1. kick_same_device_id → duplicate_login（Connection.Kick）
    # 2. online_on_platform = Tracker.list_by_platform(...)
    # 3. max = AppConfig.get_int_map(:max_devices_per_platform)[platform]
    # 4. if count >= max → policy
  end
end
```

| 场景 | 行为 |
|------|------|
| 同 `device_id` 已在线 | `CMD_KICK` `duplicate_login`，不计入新名额 |
| 未超限 | `:ok`，继续 `AUTH_RESP` |
| 超限 + `reject` | `CMD_ERROR` 1004，关连接 |
| 超限 + `kick_oldest_on_platform` | 最旧设备 `CMD_KICK` `device_limit`，再 `AUTH_RESP` |

`IM.Connection.Kick` 负责下发 `KickNotify`（含 `kicker` 设备信息、`clear_local_data`）。管理端踢人/封禁见 [auth.md](../../design/auth.md) §9.8；离线 pending 由 `IM.Services.Kick` 写 `user_devices.clear_local_data_pending`。

---

## 6. 验收要点（P2-02）

| 场景 | 期望 |
|------|------|
| 建连 10s 无 AUTH | 静默断开 |
| 未鉴权发 `MSG_SEND` | 静默断开 |
| 未鉴权发 `HEARTBEAT` | 静默断开 |
| 合法 AUTH | `AUTH_RESP` → `state=authenticated` |
| AUTH 失败 | `CMD_ERROR(1001)` + 断开 |
| **已鉴权再发 `AUTH_REQ`** | **`CMD_ERROR(1001)` + 断开** |
| 已鉴权未知 cmd | `CMD_ERROR` + 断开 |
| 合法业务包 | 正常处理，重置空闲计时 |

---

## 7. 测试示例

```elixir
test "rejects AUTH after already authenticated" do
  socket = auth_ok(build_socket())

  assert {:stop, _, _} =
           UserSocket.handle_in({:binary, encode_auth_packet()}, socket)
end

test "rejects MSG_SEND before auth" do
  assert {:stop, :state_violation, _} =
           UserSocket.handle_in({:binary, encode_msg_send()}, build_socket())
end
```
