# IM 协议客户端（Elixir 共享库）

`IM.Client.*`：与 IM 服务端协议一致的 **无头客户端库**——Packet Codec、WebSocket 连接、AUTH/心跳、REST 登录、发消息及群/室/好友等命令封装。

| 项 | 说明 |
| --- | --- |
| 性质 | **共享库**，不打进 IM Release |
| 消费者 | `loadtest`、IM 侧 `test/im_client/protocol/` E2E |
| Proto | `lib/pb/` 与 `im` 同源，由 `mise run proto-gen` 同步 |

设计：[test-client.md](../../../docs/design/test-client.md)  
实现：[test-client impl](../../../docs/implementation/elixir/test-client.md)  
Kiro Spec：[im-client-c0-c1](../../../docs/specs-index.md#子项目-spec) · [`.kiro/specs/im-client-c0-c1/`](../../../.kiro/specs/im-client-c0-c1/)

---

## 前置条件

- 与 `apps/elixir/im` 相同工具链（mise + Elixir 1.19）
- 仓库根目录 `mise install`

---

## 启动 / 使用

本仓库 **无独立 HTTP 服务**。在 Mix 项目中以 path 依赖引用：

```elixir
# mix.exs
{:im_client, path: "../im_client", only: :test}
```

### 本地开发与测试

```bash
# 仓库根
mise run im_client:test

# 或进入目录
cd apps/elixir/im_client
mix deps.get
mix test
mix docs    # 或 mise run im_client:docs → doc/index.html
```

### 在代码中使用

```elixir
alias IM.Client.{Connection, REST, Scenario}

# REST 登录
{:ok, login} = REST.login(base_url, app_key, user_id, password, device_id: "d1")

# WebSocket
{:ok, pid} = Connection.start_link(url: ws_url)
{:ok, _} = Connection.authenticate(pid, login)
{:ok, ack} = Connection.send_message(pid, %{...})
```

协议 E2E 示例见 `apps/elixir/im/test/im_client/protocol/`。

---

## 配置

| 项 | 说明 |
| --- | --- |
| `config/config.exs` | 库默认项（极少） |
| 运行时 | **由调用方**传入 `base_url` / `ws_url` / token，库本身不读生产 Secret |
| Proto 同步 | 改 `proto/` 后须 `mise run proto-gen`（同步至 `im` 与 `im_client/lib/pb/`） |

测试环境 URL 由 IM 侧 `config/test.exs` 的 `protocol_e2e_base_url` / `protocol_e2e_ws_url` 提供，**不是** im_client 自有配置。

---

## 线上部署

**无需单独部署。** 本库仅作为：

1. **压测 Release**（`deploy/elixir/loadtest/Dockerfile`）的编译依赖；
2. **CI / ExUnit** 的测试依赖。

生产 IM 集群不安装、不运行 im_client 进程。

---

## 相关文档

- [文档总索引](../../../docs/README.md)
- [功能模块对照表](../../../docs/module-map.md)
- [Kiro Spec 索引](../../../docs/specs-index.md)
- [loadtest README](../loadtest/README.md)
- [IM 主服务 README](../im/README.md)
- [apps 总览](../../README.md)
