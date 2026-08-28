# 好友系统 - Elixir 实现

| 项 | 内容 |
|------|------|
| 语言 | Elixir |
| 设计文档 | [friend.md](../../design/friend.md) |
| Roadmap | Phase 8：P8-05–P8-08（纳入）；P8-09（**deferred**，租户级非好友禁发） |

> **文档分级**：边缘模块 impl。Phase 3 单聊不依赖好友；拉黑 P8-08。WS / REST 经 `Dispatch` → `IM.Services.Friend`。详见 [dual-channel-api.md](dual-channel-api.md)。

---

## 1. 模块划分

| 模块 | 职责 |
| --- | --- |
| `IM.Application.Dispatch` | `CMD_FRIEND_*` → `IM.Services.Friend` |
| `IM.Services.Friend` | Facade；各 `*Handler` 子模块 |
| `IM.Services.Friend.*Handler` | 单项业务（增删改查、请求处理） |
| `IM.Delivery.Router` | `CMD_FRIEND_*_PUSH` 扇出 |
| `IM.Stores.FriendshipStore` / `FriendRequestStore` | 持久化 |

```elixir
defmodule IM.Services.Friend do
  alias IM.Services.Friend.{
    AddHandler,
    AcceptHandler,
    RejectHandler,
    DeleteHandler,
    BlockHandler,
    ListHandler
  }

  def add_friend(req, ctx), do: AddHandler.handle(req, ctx)
  def accept_friend(req, ctx), do: AcceptHandler.handle(req, ctx)
  def reject_friend(req, ctx), do: RejectHandler.handle(req, ctx)
  def delete_friend(req, ctx), do: DeleteHandler.handle(req, ctx)
  def block_user(req, ctx), do: BlockHandler.handle(req, ctx)
  def list_friends(req, ctx), do: ListHandler.handle(req, ctx)
end
```

---

## 2. 接受好友请求处理器

```elixir
defmodule IM.Services.Friend.AcceptHandler do
  alias IM.Delivery.Router
  alias IM.Stores.{FriendshipStore, FriendRequestStore}

  def handle(req, context) do
    with {:ok, request} <- get_request(req.request_id),
         :ok <- validate_request(request, context),
         {:ok, _} <- create_friendship(request, req) do
      notify = build_accept_notify(context)
      Router.deliver(notify, [{request.from_user_id, :all}], cmd: :CMD_FRIEND_ACCEPT_PUSH)
      {:ok, %{friend_user_id: request.from_user_id, status: :accepted}}
    end
  end

  defp create_friendship(request, req) do
    with {:ok, _} <- FriendshipStore.create(%{
           user_id: request.to_user_id,
           friend_user_id: request.from_user_id,
           remark: req.remark
         }),
         {:ok, _} <- FriendshipStore.create(%{
           user_id: request.from_user_id,
           friend_user_id: request.to_user_id
         }) do
      :ok
    end
  end
end
```

---

## 3. WS / REST 适配

```elixir
# IM.WebSocket.Commands.FriendAccept（薄）
def handle(packet, socket) do
  ctx = MessageContext.from_socket(socket, source: :websocket)
  {:ok, req} = decode(packet, FriendAcceptReq)

  case IM.Application.Dispatch.execute(:CMD_FRIEND_ACCEPT_REQ, req, ctx) do
    {:ok, resp} -> reply(packet, resp, socket)
    {:error, %ErrorBody{} = err} -> error(packet, err, socket)
  end
end

# IMWeb.Api.V1.FriendController（薄）
def accept(conn, params) do
  ctx = MessageContext.from_conn(conn, source: :http)
  {:ok, resp} = IM.Application.Dispatch.execute(:CMD_FRIEND_ACCEPT_REQ, params, ctx)
  json(conn, resp)
end
```

---

## 4. 权限校验

热缓存见 [permission-cache.md](../../design/permission-cache.md)；实现见 [permission-cache.md](permission-cache.md)。

```elixir
defmodule IM.Services.Friend do
  alias IM.Permission.BlockCache

  def check_send_permission(app_key, from_user_id, to_user_id) do
    cond do
      BlockCache.blocked?(app_key, to_user_id, from_user_id) -> {:error, :blocked}
      require_friend_to_send?() and not friends?(from_user_id, to_user_id) -> {:error, :not_friend}
      true -> :ok
    end
  end
end
```

`IM.Services.SingleChat` 在 `send/2` 路径调用；`require_friend_to_send?/0` 对应 P8-09（deferred）。

---

## 5. 好友请求过期清理

```elixir
def cleanup_expired_requests do
  expired =
    Repo.all(
      from r in FriendRequest,
        where: r.status == :pending and r.expires_at < ^DateTime.utc_now()
    )

  Enum.each(expired, fn request ->
    Repo.update!(%{request | status: :expired})
  end)
end
```

Oban Worker 或 `:timer` 定时执行；见 roadmap P8-07。

---

## 6. 测试要点

- 同一 `accept` 场景：**WS 集成测试 + REST 集成测试**，断言落库与 `CMD_FRIEND_ACCEPT_PUSH` 一致。
- 拉黑：单聊 `CMD_MSG_SEND` 返回 `CODE_MSG_NO_PERMISSION` 或约定错误码（见 P8-08）。
