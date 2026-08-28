#!/usr/bin/env bash
# LT-40：长时间稳定性循环。默认 72h；本地可 DURATION_SEC=600。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

: "${APP_KEY:?APP_KEY required}"
DURATION_SEC="${DURATION_SEC:-259200}"
USERS="${USERS:-50}"
CONCURRENCY="${CONCURRENCY:-25}"
ITERATIONS="${ITERATIONS:-20}"
SLEEP_SEC="${SLEEP_SEC:-300}"
mkdir -p tmp

END=$(( $(date +%s) + DURATION_SEC ))
ROUND=0
echo "[soak] duration=${DURATION_SEC}s users=${USERS}"

while [ "$(date +%s)" -lt "$END" ]; do
  ROUND=$((ROUND + 1))
  echo "[soak] round=${ROUND}"
  mise run loadtest:run -- connection_load \
    --app-key "$APP_KEY" \
    --users "$USERS" \
    --concurrency "$CONCURRENCY" \
    --report "tmp/soak-connection-$ROUND.json" || true
  mise run loadtest:run -- message_flood \
    --app-key "$APP_KEY" \
    --users "$((USERS / 2))" \
    --iterations "$ITERATIONS" \
    --report "tmp/soak-flood-$ROUND.json" || true
  sleep "$SLEEP_SEC"
done

echo "[soak] done rounds=${ROUND}"
