defmodule IMWeb.Router do
  @moduledoc """
  HTTP 路由：健康检查、WebSocket 升级、`/api/v1` REST。
  """

  use Phoenix.Router

  import Plug.Conn
  import Phoenix.Controller

  pipeline :api do
    plug(:accepts, ["json"])
  end

  pipeline :api_traced do
    plug(:accepts, ["json"])
    plug(IMWeb.Plugs.RequireTraceId)
    plug(IMWeb.Plugs.LogContext)
  end

  pipeline :api_auth do
    plug(:accepts, ["json"])
    plug(IMWeb.Plugs.RequireTraceId)
    plug(IMWeb.Plugs.BearerAuth)
    plug(IMWeb.Plugs.LogContext)
  end

  pipeline :internal do
    plug(:accepts, ["json"])
    plug(IMWeb.Plugs.RequireTraceId)
    plug(IMWeb.Plugs.RequireCallerService)
    plug(IMWeb.Plugs.LogContext)
  end

  scope "/", IMWeb do
    pipe_through(:api)

    get("/health/live", HealthController, :live)
    get("/health/ready", HealthController, :ready)
    get("/health", HealthController, :live)
    get("/metrics", MetricsController, :index)
    get("/ws", WsController, :upgrade)
  end

  scope "/api/v1", IMWeb.Api.V1 do
    pipe_through(:api_traced)

    post("/sessions", SessionController, :create)
  end

  scope "/api/v1", IMWeb.Api.V1 do
    pipe_through(:api_auth)

    delete("/sessions/current", SessionController, :delete_current)
    post("/devices/:device_id/local-data-cleared", DeviceController, :local_data_cleared)
    put("/devices/:device_id/push-token", DeviceController, :update_push_token)
    post("/devices/:device_id/ban", DeviceController, :ban)

    post("/messages", MessageController, :create)
    get("/messages/inbox", MessageController, :inbox)
    get("/conversations", ConversationController, :index)
    post("/messages/ack", MessageController, :ack)
    post("/messages/ack-batch", MessageController, :ack_batch)
    post("/messages/read", MessageController, :read)
    post("/messages/:msg_id/recall", MessageController, :recall)
    post("/messages/:msg_id/edit", MessageController, :edit)
    get("/conversations/:conv_id/messages", MessageController, :conversation_messages)

    post("/passthrough", PassthroughController, :create)

    get("/friends", FriendController, :index)
    get("/friends/requests", FriendController, :requests)
    post("/friends", FriendController, :add)
    post("/friends/accept", FriendController, :accept)
    post("/friends/reject", FriendController, :reject)
    delete("/friends", FriendController, :delete)
    post("/friends/block", FriendController, :block)
    post("/friends/unblock", FriendController, :unblock)
    put("/friends/remark", FriendController, :set_remark)

    post("/groups", GroupController, :create)
    post("/groups/:group_id/dismiss", GroupController, :dismiss)
    post("/groups/:group_id/join", GroupController, :join)
    post("/groups/:group_id/leave", GroupController, :leave)
    post("/groups/:group_id/kick", GroupController, :kick)
    post("/groups/:group_id/invite", GroupController, :invite)
    post("/groups/:group_id/admins", GroupController, :set_admin)
    delete("/groups/:group_id/admins", GroupController, :remove_admin)
    post("/groups/:group_id/transfer", GroupController, :transfer)
    post("/groups/:group_id/mute", GroupController, :mute)
    patch("/groups/:group_id", GroupController, :update)

    post("/rooms", RoomController, :create)
    post("/rooms/:room_id/dismiss", RoomController, :dismiss)
    post("/rooms/:room_id/join", RoomController, :join)
    post("/rooms/:room_id/leave", RoomController, :leave)
    post("/rooms/:room_id/kick", RoomController, :kick)
    patch("/rooms/:room_id", RoomController, :update)
    post("/rooms/:room_id/messages", RoomController, :create_message)

    put("/channels/subscriptions", ChannelController, :subscribe)
    delete("/channels/subscriptions", ChannelController, :unsubscribe)
    post("/channels/publish", ChannelController, :publish)
  end

  scope "/internal/v1", IMWeb.Internal.V1 do
    pipe_through(:internal)

    post("/channels/:namespace/:name/publish", ChannelController, :publish)
    post("/users/:user_id/provision", UserController, :provision)
    post("/users/:user_id/kick", UserController, :kick)
    post("/users/:user_id/messages", UserController, :create_message)
    post("/devices/:device_id/kick", DeviceController, :kick)
    post("/devices/:device_id/ban", DeviceController, :ban)
  end
end
