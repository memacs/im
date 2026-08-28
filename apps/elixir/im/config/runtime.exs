# 启动时求值，是 Release 中唯一能读取环境变量的配置文件。
# 变量来源见 deploy/elixir/im/k8s/im/configmap.yaml 与 secret.yaml，
# 说明见 docs/implementation/elixir/release-deploy-test.md §环境变量与配置。
import Config

# PHX_SERVER=true 时启动 HTTP 监听（`bin/im start` 走这条路径）
if System.get_env("PHX_SERVER") do
  config :im, IMWeb.Endpoint, server: true
end

if config_env() == :prod do
  # 缺失即在启动时崩溃并给出明确原因，好过运行期出现难以定位的错误
  database_url = System.fetch_env!("DATABASE_URL")
  secret_key_base = System.fetch_env!("SECRET_KEY_BASE")
  host = System.fetch_env!("PHX_HOST")

  port = String.to_integer(System.get_env("PORT") || "4000")
  scheme = System.get_env("PHX_SCHEME") || "http"
  url_port = String.to_integer(System.get_env("PHX_URL_PORT") || to_string(port))

  config :im, IM.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: if(System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: [])

  config :im, IMWeb.Endpoint,
    url: [host: host, port: url_port, scheme: scheme],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base

  # Redis（P9-02）与节点角色（P9-01）
  redis_url = System.get_env("REDIS_URL")

  if is_binary(redis_url) and redis_url != "" do
    config :im,
      redis_url: redis_url,
      cache: IM.Cache.Redis,
      node_role: System.get_env("IM_NODE_ROLE") || "access"
  else
    config :im,
      redis_url: nil,
      node_role: System.get_env("IM_NODE_ROLE") || "access"
  end

  # libcluster（P9-01）：CLUSTER_STRATEGY=kubernetes|epmd
  case System.get_env("CLUSTER_STRATEGY") do
    "kubernetes" ->
      service = System.get_env("CLUSTER_SERVICE") || "im-headless"
      app_name = System.get_env("CLUSTER_APP_NAME") || "im"

      config :im,
        cluster_topologies: [
          im: [
            strategy: Cluster.Strategy.Kubernetes.DNS,
            config: [
              service: service,
              application_name: app_name
            ]
          ]
        ]

    "epmd" ->
      hosts =
        (System.get_env("CLUSTER_HOSTS") || "")
        |> String.split(",", trim: true)
        |> Enum.map(&String.to_atom/1)

      config :im,
        cluster_topologies: [
          im: [
            strategy: Cluster.Strategy.Epmd,
            config: [hosts: hosts]
          ]
        ]

    _ ->
      :ok
  end

  # 生产默认 :warning（见 docs/design/observability.md §2.6）；排障时可临时调高
  log_level =
    case System.get_env("LOG_LEVEL") do
      "debug" -> :debug
      "info" -> :info
      "error" -> :error
      _ -> :warning
    end

  config :logger, level: log_level
end

# Oban Cron：TTL 清理 / 权限对账（对应 *_AUTO=true）
if config_env() != :test do
  crontab =
    []
    |> then(fn acc ->
      ttl_purge_auto =
        case System.get_env("TTL_PURGE_AUTO") do
          nil -> Application.get_env(:im, :ttl_purge_auto, false)
          v -> v in ~w(true 1)
        end

      if ttl_purge_auto do
        cron = System.get_env("TTL_PURGE_CRON") || "*/15 * * * *"
        [{cron, IM.Workers.TtlPurge} | acc]
      else
        acc
      end
    end)
    |> then(fn acc ->
      reconcile_auto =
        case System.get_env("PERMISSION_RECONCILE_AUTO") do
          nil -> Application.get_env(:im, :permission_reconcile_auto, false)
          v -> v in ~w(true 1)
        end

      if reconcile_auto do
        cron = System.get_env("PERMISSION_RECONCILE_CRON") || "0 */6 * * *"
        [{cron, IM.Workers.PermissionReconcile} | acc]
      else
        acc
      end
    end)
    |> then(fn acc ->
      unread_flush_auto =
        case System.get_env("UNREAD_FLUSH_AUTO") do
          nil -> Application.get_env(:im, :unread_flush_auto, false)
          v -> v in ~w(true 1)
        end

      if unread_flush_auto do
        cron = System.get_env("UNREAD_FLUSH_CRON") || "*/5 * * * *"
        [{cron, IM.Workers.UnreadFlush} | acc]
      else
        acc
      end
    end)

  if crontab != [] do
    prev = Application.get_env(:im, Oban, [])

    config :im, Oban,
           Keyword.merge(prev, plugins: [{Oban.Plugins.Cron, crontab: crontab}])
  end
end

# Kafka 旁路（P9-03）：所有环境可读 env
# KAFKA_BROKERS=host1:9092,host2:9092
# EVENT_BUS_ENABLED=true
# EVENT_BUS_PRODUCER=brod|memory
kafka_brokers =
  case System.get_env("KAFKA_BROKERS") do
    nil ->
      []

    "" ->
      []

    raw ->
      raw
      |> String.split(",", trim: true)
      |> Enum.flat_map(fn hostport ->
        case String.split(hostport, ":", parts: 2) do
          [host, port] ->
            case Integer.parse(port) do
              {p, ""} when p > 0 -> [{host, p}]
              _ -> []
            end

          _ ->
            []
        end
      end)
  end

if kafka_brokers != [] or System.get_env("EVENT_BUS_ENABLED") in ~w(true 1 false 0) or
     System.get_env("EVENT_BUS_PRODUCER") in ~w(brod memory) do
  event_bus_enabled =
    case System.get_env("EVENT_BUS_ENABLED") do
      v when v in ~w(true 1) -> true
      v when v in ~w(false 0) -> false
      _ -> Application.get_env(:im, :event_bus_enabled, false)
    end

  event_bus_producer =
    case System.get_env("EVENT_BUS_PRODUCER") do
      "brod" when kafka_brokers != [] -> IM.EventBus.Producer.Brod
      "memory" -> IM.EventBus.Producer.Memory
      _ when kafka_brokers != [] and event_bus_enabled -> IM.EventBus.Producer.Brod
      _ -> IM.EventBus.Producer.Memory
    end

  client_id =
    case System.get_env("KAFKA_CLIENT_ID") do
      nil -> :im_kafka
      "" -> :im_kafka
      name -> String.to_atom(name)
    end

  prev_kafka = Application.get_env(:im, :event_bus_kafka, [])

  config :im,
    event_bus_enabled: event_bus_enabled,
    event_bus_producer: event_bus_producer,
    event_bus_kafka:
      prev_kafka
      |> Keyword.put(:brokers, kafka_brokers)
      |> Keyword.put(:client_id, client_id)
end


