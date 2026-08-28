import Config

# database 带 MIX_TEST_PARTITION 后缀，支持 `mix test --partitions N` 并行
config :im, IM.Repo,
  hostname: System.get_env("PGHOST") || "localhost",
  port: String.to_integer(System.get_env("PGPORT") || "5432"),
  username: System.get_env("PGUSER") || "im",
  password: System.get_env("PGPASSWORD") || "im_dev_only",
  database: "im_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :im, IMWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test_only_secret_key_base_at_least_64_bytes_long_xxxxxxxxxxxxxxxxxxx",
  server: false

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime
