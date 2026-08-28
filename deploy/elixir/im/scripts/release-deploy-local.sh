#!/usr/bin/env bash
# 本地黄金路径：mix release（Docker 内）→ 镜像 → K8s 部署 → 冒烟检查
# 与线上构建/部署形态一致，见 docs/implementation/elixir/release-deploy-test.md
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
cd "$ROOT"

IMAGE="${IM_IMAGE:-im:local}"
DOCKERFILE="${IM_DOCKERFILE:-deploy/elixir/im/Dockerfile}"
OVERLAY="${IM_K8S_OVERLAY:-deploy/elixir/im/k8s/overlays/local}"
NAMESPACE="${IM_K8S_NAMESPACE:-im-dev}"
SKIP_BUILD="${IM_SKIP_BUILD:-0}"
SKIP_DEPLOY="${IM_SKIP_DEPLOY:-0}"
IM_APP="${IM_APP_DIR:-apps/elixir/im}"

log() { printf '==> %s\n' "$*"; }

if ! kubectl cluster-info &>/dev/null; then
  echo "error: kubectl 无法连接集群（请确认 OrbStack Kubernetes 已启用）" >&2
  exit 1
fi

if [[ "$SKIP_BUILD" != "1" ]]; then
  if [[ ! -f "$IM_APP/mix.exs" ]]; then
    echo "error: 未找到 $IM_APP/mix.exs，请先完成 Phase 0 脚手架（P0-01）再构建 Release 镜像" >&2
    exit 1
  fi
  log "Building Release image (same as production Dockerfile): $IMAGE"
  docker build -f "$DOCKERFILE" -t "$IMAGE" .
else
  log "Skipping docker build (IM_SKIP_BUILD=1)"
fi

if [[ "$SKIP_DEPLOY" != "1" ]]; then
  log "Applying Kubernetes overlay: $OVERLAY"
  kubectl apply -k "$OVERLAY"

  log "Waiting for dependencies..."
  kubectl -n "$NAMESPACE" rollout status deployment/redis --timeout=120s
  kubectl -n "$NAMESPACE" rollout status deployment/postgres --timeout=180s

  if kubectl -n "$NAMESPACE" get deployment im &>/dev/null; then
    log "Waiting for IM Release rollout..."
    kubectl -n "$NAMESPACE" rollout status deployment/im --timeout=300s
  fi
else
  log "Skipping kubectl apply (IM_SKIP_DEPLOY=1)"
fi

log "Cluster status ($NAMESPACE):"
kubectl -n "$NAMESPACE" get pods,svc

if kubectl -n "$NAMESPACE" get deployment im &>/dev/null; then
  log "Smoke: port-forward and hit /health (run in another terminal):"
  echo "  kubectl -n $NAMESPACE port-forward svc/im 4000:4000"
  echo "  curl -sf http://localhost:4000/health"
fi

log "Done."
