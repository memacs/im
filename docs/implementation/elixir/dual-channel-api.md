# 双通道 API（WebSocket + REST）- Elixir 实现

| 项 | 内容 |
|------|------|
| 语言 | Elixir |
| **HTTP 接口参考** | [http-api-reference.md](http-api-reference.md)（逐端点 + 示例） |
| 设计文档 | [dual-channel-api.md](../../design/dual-channel-api.md) |
| 上下文 | [message-context.md](message-context.md) |
| Roadmap | Phase 2（P2-10、P2-11）及各 Phase REST 适配 |

---

## 1. 模块划分

| 模块 | 职责 |
|------|------|
| `IM.Protocol.Router` | WS 按 `cmd` 选 `Commands.*`；鉴权态门禁；`:telemetry.span`；**无业务** |
| `IM.WebSocket.Commands.*` | 解 payload、组 `MessageContext`、调 `Dispatch` |
| `IM.Application.Dispatch` | **唯一** cmd → Service 映射；WS/REST/Kafka 均调用 |
| `IM.Ingress.Http` | Plug 鉴权、body 解析 → `Dispatch.execute/3` → JSON 响应 |
| `IM.Plug.BearerAuth` | 客户端 `/api/v1`：校验 `access_token` |
| `IM.Plug.RequireTraceId` | **所有 HTTP**：校验必填 `X-Trace-Id`（pipeline 最前） |
| `IM.Plug.InternalCaller` | 内部 `/internal/v1`：校验 `X-IM-Caller-Service`、IP 封禁 |
| `IMWeb.Api.V1.*Controller` | 客户端 REST 路由 |
| `IMWeb.Internal.V1.*Controller` | 内部 REST 路由 |
| `IM.Services.*` | 业务实现（禁止被 Controller 绕过） |
| `IM.Delivery.Router` | Service 扇出下行 PUSH（与 Dispatch 无关） |

WS 路径：`Codec` → `Protocol.Router` → `Commands.*` → `Dispatch` → `Services.*`。详见设计文档 [dual-channel-api.md](../../design/dual-channel-api.md) §4.1。

目录（与 [project-structure.md](project-structure.md) 对齐）：

```text
lib/im/
├── application/
│   └── dispatch.ex          # cmd 注册表 + execute/3
├── ingress/
│   ├── websocket.ex         # WS 侧适配
│   └── http.ex              # REST 侧适配
├── services/                # 业务（已有）
lib/im_web/
├── controllers/api/v1/      # 客户端 REST（Bearer）
├── controllers/internal/v1/ # 内部 REST（Caller-Service）
```

---

## 2. Dispatch（核心）

```elixir
defmodule IM.Application.Dispatch do
  @moduledoc """
  将 CmdType + payload + MessageContext 分发到唯一 Service 实现。
  WebSocket 与 REST 必须经此模块，禁止复制业务逻辑。
  """

  @callback execute(non_neg_integer(), map() | struct(), IM.Domain.MessageContext.t()) ::
              {:ok, term()} | {:error, IM.Domain.Error.t()}

  def execute(cmd, payload, %IM.Domain.MessageContext{} = ctx) do
    with :ok <- authorize_context(cmd, ctx),
         {:ok, result} <- route(cmd).handle(payload, ctx) do
      {:ok, result}
    end
  end

  defp route(:CMD_MSG_SEND), do: IM.Services.Message
  defp route(:CMD_OFFLINE_PULL_REQ), do: IM.Services.Offline
  defp route(:CMD_FRIEND_ADD_REQ), do: IM.Services.Friend
  # ... 与 IM.WebSocket.Commands 一一对应
end
```

WebSocket Command 模块 **只做**：

```elixir
def handle(packet, socket) do
  {:ok, req} = IM.Protocol.decode_payload(packet, :MsgSendReq)
  ctx = IM.Domain.MessageContext.from_socket(socket, packet)

  case IM.Application.Dispatch.execute(:CMD_MSG_SEND, req, ctx) do
    {:ok, resp} -> {:reply, IM.Protocol.Reply.success(packet, resp), socket}
    {:error, err} -> {:reply, IM.Protocol.Reply.error(packet, err), socket}
  end
end
```

---

## 3. REST Controller（薄适配）

```elixir
defmodule IMWeb.Api.V1.MessageController do
  use IMWeb, :controller

  def create(conn, _params) do
    IM.Ingress.Http.dispatch(conn, :CMD_MSG_SEND, &parse_msg_send/1)
  end
end
```

```elixir
defmodule IM.Ingress.Http do
  def dispatch(conn, cmd, parse_fun) do
    with {:ok, ctx} <- IM.Auth.Plug.current_context(conn),
         {:ok, payload} <- parse_fun.(conn),
         {:ok, resp} <- IM.Application.Dispatch.execute(cmd, payload, ctx) do
      json(conn, IM.Ingress.HttpCodec.encode_resp(cmd, resp))
    else
      {:error, err} -> IMWeb.FallbackController.call(conn, err)
    end
  end
end
```

`IMWeb.FallbackController` 将 `ErrorCode` 映射为 HTTP 状态 + JSON（与 `ErrorBody` 一致）。

---

## 4. MessageContext 差异

| 字段 | WebSocket | REST |
| --- | --- | --- |
| `source` | `:websocket` | `:http` |
| `device_id` | `socket.assigns` | 可选 header `X-Device-Id` 或 body |
| `packet_cid` | `Packet.cid` | `Idempotency-Key` 或 body |
| `socket` | 连接 pid | `nil` |

---

## 5. 测试（TDD）

与 [`agent.md`](../../../agent.md)「测试驱动开发」一致：**DI 优先**（内存 Store/Cache）、**禁止 ExMachina**、**禁止 sleep 同步**（用 `assert_receive` / `GenServer.call`）。

每个 Service 能力至少两组用例：

```elixir
describe "send private message" do
  test "via websocket packet", %{conn: conn} ... end
  test "via rest api", %{conn: conn} do
    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> post(~p"/api/v1/messages", msg_send_json)
    |> json_response(200)

  assert same_message_in_db(...)
  end
end
```

---

## 6. Phase 落地顺序

| Roadmap | 内容 |
| --- | --- |
| P2-10 | `Dispatch` 注册表 + WS 改经 Dispatch |
| P2-11 | `:api` pipeline、Bearer、`FallbackController`、健康检查外首个 REST 样例 |
| P3+ | 每完成 WS Handler，**同任务** 增加对应 REST 路由与双通道测试 |
