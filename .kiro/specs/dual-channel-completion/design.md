# Design: dual-channel completion

## Dispatch

`execute(cmd, payload, ctx)` 映射到 `IM.Services.*`。WS Command：decode → Dispatch → Reply/PubSub。REST：parse JSON → Dispatch → JSON。

## REST 路径

见 dual-channel-api §3.1；控制器：Message / Friend / Group / Room / Passthrough / Channel（已有）。

## 测试

`test/im/application/dispatch_test.exs`、`test/im_web/controllers/api/v1/*_test.exs`。
