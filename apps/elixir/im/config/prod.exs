import Config

# 生产的 URL、密钥、连接串全部在 runtime.exs 读取环境变量。
# 此处只放编译期即可确定的静态项。
config :logger, level: :warning

# DD-028：生产 stdout 单行 NDJSON（自研 Formatter，无 logger_json 依赖）
config :logger, :default_handler, formatter: {IM.Log.JsonFormatter, %{}}
