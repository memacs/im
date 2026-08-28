#!/usr/bin/env bash
# 解析本地 Postgres 端口，供 mise run test / ecto / phx.server 使用。
#
# OrbStack/K8s 的 Postgres 在集群内 5432，经 pg-forward 映射到本机 15432。
# test.exs / dev.exs 默认 PGPORT=5432（兼容 GHA postgres service），
# 直接 mise run test 而不经本脚本会连错端口 → connection refused。
#
# 用法（mise 任务内）：
#   set -e
#   # shellcheck source=deploy/elixir/im/scripts/resolve-pg-port.sh
#   source deploy/elixir/im/scripts/resolve-pg-port.sh
#   cd apps/elixir/im && mix test
#
# 已设置 PGPORT 时尊重调用方（如 CI 可 PGPORT=5432 mise run test）。

set -euo pipefail

if [[ -n "${PGPORT:-}" ]]; then
  export PGPORT
  return 0 2>/dev/null || exit 0
fi

_pick_port() {
  if command -v nc >/dev/null 2>&1; then
    nc -z localhost 15432 2>/dev/null && echo 15432 && return 0
    nc -z localhost 5432 2>/dev/null && echo 5432 && return 0
  elif command -v bash >/dev/null 2>&1; then
    (echo >/dev/tcp/127.0.0.1/15432) 2>/dev/null && echo 15432 && return 0
    (echo >/dev/tcp/127.0.0.1/5432) 2>/dev/null && echo 5432 && return 0
  fi
  return 1
}

if picked=$(_pick_port); then
  export PGPORT="$picked"
  return 0 2>/dev/null || exit 0
fi

cat >&2 <<'EOF'
错误：localhost 上未检测到 Postgres（15432 或 5432）。

OrbStack / 本地 K8s：
  终端 A：mise run k8s-up && mise run pg-forward   # 转发到 localhost:15432
  终端 B：mise run test

GitHub Actions：postgres service 监听 5432，workflow 应设置 PGPORT=5432。

详见 docs/implementation/elixir/local-dev-gotchas.md §Postgres 端口
EOF
return 1 2>/dev/null || exit 1
