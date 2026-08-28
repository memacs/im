#!/usr/bin/env bash
# Release 冒烟：健康检查 + Pod 内 REST 登录（见 release-smoke-auth.md）
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:4000}"
NAMESPACE="${IM_K8S_NAMESPACE:-im-dev}"
SKIP_K8S="${SMOKE_SKIP_K8S:-0}"

log() { printf '==> %s\n' "$*"; }

log "Health live: $BASE_URL/health/live"
curl -sf "$BASE_URL/health/live" | grep -q '"status":"ok"'

log "Health ready: $BASE_URL/health/ready"
curl -sf "$BASE_URL/health/ready" | grep -q '"status":"ok"'

if [[ "$SKIP_K8S" == "1" ]]; then
  log "Skipping in-pod smoke (SMOKE_SKIP_K8S=1)"
  exit 0
fi

if ! kubectl -n "$NAMESPACE" get deployment im &>/dev/null; then
  log "No deployment/im in $NAMESPACE — skip in-pod auth smoke"
  exit 0
fi

log "In-pod auth smoke (bin/smoke-auth)..."
kubectl -n "$NAMESPACE" exec deployment/im -- /app/bin/smoke-auth

log "Done."
