#!/usr/bin/env bash
# mise run flamegraph 入口：检查前置条件 → 采集 → 打印 SVG 路径
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
SCRIPT="${ROOT}/deploy/elixir/im/scripts/capture-flamegraph.sh"
NAMESPACE="${NAMESPACE:-im-dev}"
DURATION="${DURATION:-30}"
OPEN="${OPEN:-0}"

usage() {
  cat <<EOF
用法: mise run flamegraph

环境变量:
  DURATION       采样秒数（默认 30）
  NAMESPACE      K8s 命名空间（默认 im-dev）
  POD            指定 Pod（默认 app=im 第一个 Running）
  OUTPUT_DIR     输出目录（默认 artifacts/flamegraph）
  OPEN=1         采集完成后用系统默认程序打开 flame_sched.svg
  SKIP_JPPERF_CHECK=1  跳过 IM_PERF_FLAMEGRAPH 检查（不推荐）

前置: IM 已部署且 Pod Running；须 IM_PERF_FLAMEGRAPH=true 并 rollout 重启。

详见 docs/implementation/elixir/flamegraph.md
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "错误: 未找到 kubectl" >&2
  exit 1
fi

if ! command -v perl >/dev/null 2>&1; then
  echo "错误: 未找到 perl（macOS: brew install perl）" >&2
  exit 1
fi

pod="$(kubectl get pod -n "$NAMESPACE" -l app=im --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -z "$pod" ]]; then
  echo "错误: 命名空间 ${NAMESPACE} 无 Running 的 im Pod。" >&2
  echo "  请先: mise run release-deploy" >&2
  exit 1
fi

if [[ "${SKIP_JPPERF_CHECK:-0}" != "1" ]]; then
  jpperf="$(kubectl get deploy im -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="IM_PERF_FLAMEGRAPH")].value}' 2>/dev/null || true)"
  if [[ "$jpperf" != "true" ]]; then
    echo "错误: deployment/im 未设置 IM_PERF_FLAMEGRAPH=true（BEAM 须 +JPperf true 才有 Erlang 符号）。" >&2
    echo "  开启并重启:" >&2
    echo "    kubectl -n ${NAMESPACE} set env deployment/im IM_PERF_FLAMEGRAPH=true" >&2
    echo "    kubectl -n ${NAMESPACE} rollout status deployment/im" >&2
    echo "  排查完成后可关闭: kubectl -n ${NAMESPACE} set env deployment/im IM_PERF_FLAMEGRAPH-" >&2
    exit 1
  fi
fi

echo "[flamegraph] pod=${pod} namespace=${NAMESPACE} duration=${DURATION}s"
chmod +x "$SCRIPT"
"$SCRIPT" k8s

latest="$(ls -td "${ROOT}/artifacts/flamegraph"/run-k8s-* 2>/dev/null | head -1 || true)"
if [[ -z "$latest" || ! -f "${latest}/flame_sched.svg" ]]; then
  echo "错误: 未找到 flame_sched.svg，见上方 perf 输出。" >&2
  exit 1
fi

echo ""
echo "火焰图已生成:"
echo "  ${latest}/flame_sched.svg   ← 推荐（调度器栈已合并）"
echo "  ${latest}/flame.svg"
echo ""
echo "查看: open ${latest}/flame_sched.svg"

if [[ "$OPEN" == "1" ]]; then
  if command -v open >/dev/null 2>&1; then
    open "${latest}/flame_sched.svg"
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "${latest}/flame_sched.svg"
  fi
fi
