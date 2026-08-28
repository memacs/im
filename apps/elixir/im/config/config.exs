# 编译期静态配置。
# 凡来自环境变量的值（DATABASE_URL、SECRET_KEY_BASE 等）一律放 runtime.exs，
# 本文件会被编译进 Release，无法在启动时读取环境变量。
import Config

config :im,
  ecto_repos: [IM.Repo],
  generators: [timestamp_type: :utc_datetime_usec]

config :im, IMWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [json: IMWeb.ErrorJSON], layout: false],
  pubsub_server: IM.PubSub

# 日志：生产从 :warning 起打（见 docs/design/observability.md §2.6），
# 成功路径只记 Telemetry 指标，不写 Logger。
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :trace_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
