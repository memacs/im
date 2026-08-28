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

  # Redis 与节点角色在对应 Phase 接入（P9-02 / P9-01），此处先透传供各模块读取
  config :im,
    redis_url: System.get_env("REDIS_URL"),
    node_role: System.get_env("IM_NODE_ROLE") || "access"

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
