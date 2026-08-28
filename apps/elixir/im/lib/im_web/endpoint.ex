defmodule IMWeb.Endpoint do
  @moduledoc """
  HTTP / WebSocket 端点。

  监听地址与 `secret_key_base` 由 `config/runtime.exs` 从环境变量注入；
  `PHX_SERVER=true` 时才启动监听（Release 通过 `bin/im start` 设置）。

  WebSocket 二进制帧接入在 Phase 2（P2-01）挂载，
  协议见仓库根 `docs/design/protocol/protocol.md`。
  """

  use Phoenix.Endpoint, otp_app: :im

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(IMWeb.Router)
end
