# IM 实现 — 测试与代码参考

本文件为 [`SKILL.md`](SKILL.md) 的补充：测试骨架与双通道对称用例。按需阅读。

**语言**：`@doc` 与测试描述用 **简体中文**；标识符与 `@spec` 保持英文。公共 `@doc` 须含 **`## 示例`**。

---

## 服务层测试骨架

（实现模块须同时具备 `@moduledoc`、`@doc`、`@spec`，见 `agent.md`。）

```elixir
defmodule IM.Services.MessageSendTest do
  use IM.DataCase, async: true

  alias IM.Services.MessageSend

  describe "send/2 单聊" do
    test "成功时返回 msg_id 与 conv_seq" do
      # 准备夹具
      # 执行
      # assert {:ok, %{msg_id: _, conv_seq: _}} = MessageSend.send(...)
    end

    test "conv_id 不匹配时返回 {:error, :invalid}" do
      assert {:error, :invalid} = MessageSend.send(invalid_params())
    end

    test "相同 client_msg_id 幂等" do
      # 两次调用返回相同 msg_id，不重复副作用
    end
  end
end
```

---

## 协议 Codec 表驱动测试

```elixir
defmodule IM.Protocol.CodecTest do
  use ExUnit.Case, async: true

  alias IM.Protocol.Codec

  @packet_fixture "..."

  test "编解码往返一致" do
    assert {:ok, decoded} = @packet_fixture |> Codec.encode() |> Codec.decode()
    assert decoded.cmd == 100
  end
end
```

---

## 双通道对称测试（同一服务层）

```elixir
defmodule IM.DualChannel.MessageSendTest do
  use IM.DataCase, async: true

  @shared_attrs %{chat_type: 1, from: "alice", to: "bob", ...}

  describe "经 Dispatch（共用服务）" do
    setup do
      {:ok, conn: build_conn()}
    end

    test "WebSocket 路径", %{conn: _conn} do
      assert {:ok, _} = IM.Application.Dispatch.execute(:msg_send, :ws, @shared_attrs)
    end

    test "REST 路径", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/messages", @shared_attrs)
      assert %{"msg_id" => _} = json_response(conn, 201)
    end
  end
end
```

---

## WebSocket 命令处理器最小结构

```elixir
defmodule IM.WebSocket.Commands.MsgSend do
  @moduledoc """
  `CMD_MSG_SEND` 的 WebSocket 适配层；业务逻辑见 `IM.Services.MessageSend`。
  """

  alias IM.Application.Dispatch
  alias IM.Protocol.Reply

  @doc """
  解码 payload，经 Dispatch 处理，编码 ACK 响应包。

  ## 示例

      IM.WebSocket.Commands.MsgSend.handle(socket, %{
        cmd: 100,
        payload: encoded_msg_send_body
      })
      #=> {:reply, <<...>>}

  ## 返回值

  - `{:reply, binary()}` — 编码后的 ACK 包
  - `{:error, term()}` — 解码或业务失败
  """
  @spec handle(map(), map()) :: {:reply, binary()} | {:error, term()}
  def handle(socket, %{cmd: cmd, payload: payload}) do
    with {:ok, params} <- decode(payload),
         {:ok, result} <- Dispatch.execute(:msg_send, socket, params) do
      {:reply, Reply.ok(cmd, result)}
    end
  end
end
```

---

## Store Behaviour 测试替身

```elixir
# config/test.exs
config :im, message_store: IM.Stores.InMemory.MessageStore
```

生产环境在 `config/runtime.exs` 切回 `IM.Stores.Postgres.MessageStore`。

---

## 各阶段建议测试重点

| 阶段 | 优先覆盖 |
|------|----------|
| 0 | `/health`、编译、Release 启动 |
| 1 | Codec 往返、Router 命令分发、ErrorBody |
| 2 | AUTH 状态机、心跳、踢人、未鉴权超时 |
| 3 | MSG_SEND 同步 ACK、幂等、落库 |
| 4 | OFFLINE_PULL 游标分页 |
| 5–6 | 扇出、PubSub（集成 + 多节点 L4） |
| 7–8 | 撤回/编辑/好友命令对称 |
| 9 | libcluster、Kafka 旁路不阻塞主路径 |
