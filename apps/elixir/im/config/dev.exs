import Config

# 默认值与本地依赖栈一致（deploy/elixir/im/k8s/base/deps/postgres.yaml）：
#   mise run k8s-up && kubectl -n im-dev port-forward svc/postgres 5432:5432
config :im, IM.Repo,
  hostname: System.get_env("PGHOST") || "localhost",
  port: String.to_integer(System.get_env("PGPORT") || "5432"),
  username: System.get_env("PGUSER") || "im",
  password: System.get_env("PGPASSWORD") || "im_dev_only",
  database: System.get_env("PGDATABASE") || "im_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :im, IMWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT") || "4000")],
  check_origin: false,
  debug_errors: true,
  secret_key_base: "dev_only_secret_key_base_at_least_64_bytes_long_xxxxxxxxxxxxxxxxxxxx",
  server: true

config :logger, level: :debug

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
