defmodule IM.Application do
  @moduledoc """
  OTP 应用入口与顶层监督树。

  启动顺序：仓储 → 进程注册/PubSub → HTTP/WebSocket 端点。
  集群（libcluster）、Redis、Kafka 旁路在对应 Phase 接入，
  见仓库根 `docs/implementation/elixir/roadmap.md`。
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      IM.Repo,
      {Phoenix.PubSub, name: IM.PubSub},
      IMWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: IM.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    IMWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
