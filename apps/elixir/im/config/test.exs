import Config

# im_client 协议 E2E：按分区偏移 HTTP 端口，避免并行 test 冲突
partition = String.to_integer(System.get_env("MIX_TEST_PARTITION") || "0")
test_port = 4002 + partition
test_host = {127, 0, 0, 1}
test_base = "http://127.0.0.1:#{test_port}"
test_ws = "ws://127.0.0.1:#{test_port}/ws"

# database 带 MIX_TEST_PARTITION 后缀，支持 `mix test --partitions N` 并行
# 本地 OrbStack：Postgres 经 pg-forward 在 15432；`mise run test` 会自动设置 PGPORT。
# 裸跑 mix test 时默认 5432（GHA postgres service）；见 local-dev-gotchas.md
config :im, IM.Repo,
  hostname: System.get_env("PGHOST") || "localhost",
  port: String.to_integer(System.get_env("PGPORT") || "5432"),
  username: System.get_env("PGUSER") || "im",
  password: System.get_env("PGPASSWORD") || "im_dev_only",
  database: "im_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :im, IMWeb.Endpoint,
  http: [ip: test_host, port: test_port],
  secret_key_base: "test_only_secret_key_base_at_least_64_bytes_long_xxxxxxxxxxxxxxxxxxx",
  server: true

config :im,
  websocket_urls: [test_ws],
  protocol_e2e_base_url: test_base,
  protocol_e2e_ws_url: test_ws

config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

# Sequence Cache 路径下异步写 PG 与 Sandbox 不兼容，测试关闭
config :im, sequence_pg_sync: false

# 审计：测试同步落库，兼容 SQL Sandbox
config :im, audit_sync: true

# Oban：inline 在调用进程同步执行，兼容 SQL Sandbox
config :im, Oban, testing: :inline, queues: false, plugins: false

# 测试隔离：不默认写 Kafka 旁路（EventBus 单测自行开启）
config :im, event_bus_enabled: false
