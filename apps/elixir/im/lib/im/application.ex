defmodule IM.Application do
  @moduledoc """
  OTP 应用入口与顶层监督树。

  启动顺序：仓储 →（可选 Redis）→ 进程注册/PubSub → HTTP/WebSocket 端点。
  集群（libcluster）、Kafka 旁路在对应 Phase 接入，
  见仓库根 `docs/implementation/elixir/roadmap.md`。
  """

  use Application

  @impl true
  def start(_type, _args) do
    children =
      cluster_children() ++
        [
          IM.Repo,
          {Phoenix.PubSub, name: IM.PubSub},
          {Registry, keys: :unique, name: IM.Connection.DeviceRegistry},
          {Registry, keys: :duplicate, name: IM.Connection.UserRegistry}
        ] ++
        redis_children() ++
        kafka_children() ++
        [
          IM.UserTracker,
          IM.Cluster.SlowNode,
          {Task.Supervisor, name: IM.TaskSupervisor},
          IM.Delivery.MobilePush,
          IM.Permission.Invalidator,
          IM.AppConfig.Invalidator,
          {Oban, Application.fetch_env!(:im, Oban)},
          IM.Services.MsgId,
          IM.Services.StreamManager,
          IM.Gateway.CidDedup,
          IM.EventBus.Buffer,
          IM.Log.RateLimit,
          IM.Telemetry.Supervisor,
          IMWeb.Endpoint
        ]

    _ = IM.Channel.RateLimiter.ensure_table()
    _ = IM.Stores.AppConfigStore.ensure_table()
    _ = IM.Cache.Memory.ensure_table!()
    _ = IM.Permission.L1.ensure_table!()
    _ = IM.EventBus.Producer.Memory.ensure_table!()
    warn_redis_cache!()
    warn_event_bus!()

    opts = [strategy: :one_for_one, name: IM.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp redis_children do
    case Application.get_env(:im, :redis_url) do
      url when is_binary(url) and url != "" ->
        [{Redix, {url, [name: IM.Cache.Redis.Conn]}}]

      _ ->
        []
    end
  end

  defp kafka_children do
    producer = Application.get_env(:im, :event_bus_producer, IM.EventBus.Producer.Memory)

    if producer == IM.EventBus.Producer.Brod and IM.EventBus.Producer.Brod.brokers() != [] do
      [IM.EventBus.Producer.Brod.Client]
    else
      []
    end
  end

  defp cluster_children do
    topologies = IM.Cluster.topologies()

    if topologies == [] do
      []
    else
      [{Cluster.Supervisor, [topologies, [name: IM.ClusterSupervisor]]}]
    end
  end

  defp warn_redis_cache! do
    if Application.get_env(:im, :env) == :prod do
      redis_url = Application.get_env(:im, :redis_url)
      cache_impl = Application.get_env(:im, :cache, IM.Cache.Memory)
      clustered? = IM.Cluster.topologies() != []

      if (is_nil(redis_url) or redis_url == "") and cache_impl == IM.Cache.Memory do
        require Logger

        Logger.warning("""
        [IM] REDIS_URL 未配置，Cache 使用进程内 Memory。
        多节点下缓存/未读/发号将不一致；请配置 REDIS_URL（见 gap-review G-41 / deploy-guide）。
        """)
      end

      if clustered? and (is_nil(redis_url) or redis_url == "") do
        require Logger

        Logger.warning(
          "[IM] libcluster 已启用但 REDIS_URL 为空；集群部署须配置 Redis（见 deploy/elixir/im/k8s/im/configmap.yaml）。"
        )
      end
    end
  end

  defp warn_event_bus! do
    enabled = IM.EventBus.enabled?()
    producer = Application.get_env(:im, :event_bus_producer, IM.EventBus.Producer.Memory)
    brokers = IM.EventBus.Producer.Brod.brokers()

    cond do
      enabled and producer == IM.EventBus.Producer.Brod and brokers == [] ->
        require Logger

        Logger.warning("""
        [IM] EVENT_BUS_ENABLED=true 且 EVENT_BUS_PRODUCER=brod，但 KAFKA_BROKERS 为空。
        旁路 produce 将失败；请配置 broker 或改用 overlays/kafka-event-bus（见 deploy-guide §6）。
        """)

      enabled ->
        require Logger

        Logger.info("[IM] Event Bus 已启用：producer=#{inspect(producer)} brokers=#{length(brokers)}")

      true ->
        :ok
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    IMWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
