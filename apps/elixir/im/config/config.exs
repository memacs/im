# 编译期静态配置。
# 凡来自环境变量的值（DATABASE_URL、SECRET_KEY_BASE 等）一律放 runtime.exs，
# 本文件会被编译进 Release，无法在启动时读取环境变量。
import Config

config :im,
  env: config_env(),
  ecto_repos: [IM.Repo],
  generators: [timestamp_type: :utc_datetime_usec],
  token_ttl_sec: 86_400,
  auth_timeout_ms: 10_000,
  idle_timeout_ms: 90_000,
  websocket_urls: ["ws://localhost:4000/ws"],
  device_limit: %{max_per_platform: 5, policy: :kick_oldest_on_platform},
  heartbeat_interval_sec: 30,
  push_batch_max: 50,
  recall_window_sec: 120,
  edit_window_sec: 24 * 3600,
  offline_pull_limit: 200,
  burn_after_read_enabled: true,
  burn_ttl_sec_default: 0,
  burn_ttl_sec_max: 3600,
  ttl_purge_auto: false,
  msg_ttl_days: 7,
  group_inbox_fanout_async: false,
  # 权限 L1（DD-033）
  permission_l1_ttl_ms: 10_000,
  # 出站 WFQ（P3-09 / message-send-ack §7）
  priority_weight_high: 8,
  priority_weight_normal: 4,
  priority_weight_low: 1,
  priority_aging_normal_ms: 500,
  priority_aging_low_ms: 2_000,
  priority_aging_low_to_high_ms: 5_000,
  priority_max_burst: 16,
  outbound_coalesce_depth: 32,
  outbound_max_depth: 10_000,
  permission_reconcile_auto: false,
  hooks: [
    pre_send: [],
    # :fail_closed 异常时拦截发送；:fail_open 记日志后继续
    on_exception: :fail_closed
  ],
  # Kafka 旁路默认关；开启后用 Kafka→Buffer→Producer（默认 Memory）
  event_bus_enabled: false,
  event_bus: IM.EventBus.Kafka,
  event_bus_producer: IM.EventBus.Producer.Memory,
  event_bus_buffer_max: 10_000,
  allowed_payload_compressions: [
    :PAYLOAD_COMPRESSION_GZIP,
    :PAYLOAD_COMPRESSION_NONE
  ],
  # App Channel（P11）
  channel_publish_rate_per_conn: 1,
  channel_publish_burst: 2,
  channel_publish_aggregate_max: 5000,
  channel_acl: [
    subscribe_default: true,
    client_publish_default: true,
    internal_callers: :any
  ],
  # 内部 API（dual-channel §4.4.2）
  internal_api: [
    allowed_callers: :any,
    blocked_callers: []
  ],
  event_bus_kafka: [
    # 空 = 不连 Kafka；runtime 可由 KAFKA_BROKERS 注入，例如 [{"kafka", 9092}]
    brokers: [],
    client_id: :im_kafka,
    batch_size: 100,
    # 生产默认 protobuf；开发可 :json_envelope
    serialization: :protobuf,
    session_heartbeat_mode: :sampled,
    session_heartbeat_sample_rate: 0.01,
    session_heartbeat_min_interval_ms: 300_000,
    downstream_group_large_threshold: 500,
    downstream_room_mode: :room_aggregated,
    downstream_group_recipient_list_max: 500,
    downstream_room_recipient_list_max: 2000
  ],
  node_role: "all",
  cluster_rpc_timeout_ms: 5_000,
  group_fanout: [
    tree_threshold: 500,
    branching_factor: 8,
    max_depth: 4,
    rpc_timeout_ms: 2000,
    recipients_chunk: 200,
    coordinator_parallelism: 8,
    slow_node_ms: 500,
    slow_isolate_sec: 30,
    retry_max: 1,
    inbox_insert_chunk: 500,
    read_fanout_enabled: true,
    read_fanout_threshold: 500
  ]

config :im, Oban,
  repo: IM.Repo,
  queues: [inbox_fanout: 10, message_burn: 10, ttl_purge: 1],
  plugins: []

config :im, IMWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [json: IMWeb.ErrorJSON], layout: false],
  pubsub_server: IM.PubSub

# 日志：生产从 :warning 起打（见 docs/design/observability.md §2.6），
# 成功路径只记 Telemetry 指标，不写 Logger。
# metadata 键与 §2.6.0 / implementation observability §3.5 对齐（无 logger_json 时靠 formatter 打印）。
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [
    :event,
    :request_id,
    :trace_id,
    :app_key,
    :user_id,
    :device_id,
    :session_id,
    :cmd,
    :seq,
    :cid,
    :code,
    :ref_cmd,
    :reason,
    :msg_id,
    :client_msg_id,
    :duration_ms,
    :operation,
    :remote_ip,
    :caller_service,
    :channel_id,
    :namespace,
    :caller_module,
    :caller_file,
    :caller_line
  ]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
