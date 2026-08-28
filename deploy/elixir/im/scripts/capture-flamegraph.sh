#!/usr/bin/env bash
# 使用 Erlang/OTP 原生 Linux perf 支持（BeamAsm +JPperf true）采集 CPU 火焰图。
# 流程对齐官方文档：https://www.erlang.org/doc/apps/erts/beamasm.html#linux-perf-support
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
TOOLS="${ROOT}/apps/elixir/im/priv/flamegraph"
DURATION="${DURATION:-30}"
OUTPUT_DIR="${OUTPUT_DIR:-${ROOT}/artifacts/flamegraph}"
NAMESPACE="${NAMESPACE:-im-dev}"
POD="${POD:-}"
MODE="${MODE:-k8s}"
MERGE_SCHED="${MERGE_SCHED:-1}"
GENERATE_LOAD="${GENERATE_LOAD:-1}"
TITLE="${TITLE:-IM CPU Flame Graph}"

usage() {
  cat <<'EOF'
用法: capture-flamegraph.sh [local|k8s]

环境变量:
  DURATION       采样秒数（默认 30）
  OUTPUT_DIR     输出目录（默认 artifacts/flamegraph）
  MODE           local | k8s（默认 k8s）
  NAMESPACE      K8s 命名空间（默认 im-dev）
  POD            指定 Pod 名（默认 app=im 第一个 Running）
  MERGE_SCHED    1=合并 scheduler 栈（默认 1，OTP 官方 sed 建议）
  GENERATE_LOAD  1=采样前用 im rpc 制造 CPU 负载（默认 1）
  PERF_EVENT     覆盖 perf 事件（默认 Pod 内自动选 cycles:u 或 cpu-clock:u）
  TITLE          SVG 标题

前置条件（必读）:
  1. BEAM 须以 +JPperf true 启动（JIT 开启时生效）
     — 设 IM_PERF_FLAMEGRAPH=true 后重启 Pod/Release
  2. 运行本脚本的 host 须安装 perl；K8s 模式在 Pod 内执行 perf
  3. OrbStack/aarch64 等无 HW PMU 时自动用 cpu-clock:u

产出:
  perf.data / out.perf / out.folded / flame.svg / flame_sched.svg
EOF
}

require_host_tools() {
  if ! command -v perl >/dev/null 2>&1; then
    echo "错误: 未找到 perl（macOS: brew install perl）" >&2
    exit 1
  fi
  for script in stackcollapse-perf.pl flamegraph.pl; do
    if [[ ! -x "${TOOLS}/${script}" ]]; then
      echo "错误: 缺少 ${TOOLS}/${script}" >&2
      exit 1
    fi
  done
}

require_perf_local() {
  if ! command -v perf >/dev/null 2>&1; then
    echo "错误: 未找到 perf，local 模式须 Linux 宿主机" >&2
    exit 1
  fi
}

require_perf_k8s() {
  local pod=$1
  if ! kubectl exec -n "$NAMESPACE" "$pod" -- sh -c 'command -v perf >/dev/null'; then
    echo "错误: Pod 内未找到 perf，请重建镜像（Dockerfile 含 linux-perf）" >&2
    exit 1
  fi
}

resolve_pod() {
  if [[ -n "$POD" ]]; then
    echo "$POD"
    return
  fi
  kubectl get pod -n "$NAMESPACE" -l app=im \
    --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}'
}

beam_pid_local() {
  pgrep -o -f 'beam\.smp' || pgrep -o -f 'erl'
}

beam_pid_k8s() {
  local pod=$1
  kubectl exec -n "$NAMESPACE" "$pod" -- sh -c 'pgrep -o beam.smp || pgrep -o erl'
}

perf_event_in_pod() {
  local pod=$1
  if [[ -n "${PERF_EVENT:-}" ]]; then
    echo "$PERF_EVENT"
    return
  fi
  kubectl exec -n "$NAMESPACE" "$pod" -- sh -c \
    'if perf list hw 2>/dev/null | grep -qE "^[[:space:]]*cycles"; then echo cycles:u; else echo cpu-clock:u; fi'
}

check_jpperf_local() {
  local pid=$1
  if tr '\0' ' ' <"/proc/${pid}/cmdline" | grep -q 'JPperf'; then
    return 0
  fi
  echo "错误: BEAM(pid=${pid}) 未启用 +JPperf true。" >&2
  echo "  请设 IM_PERF_FLAMEGRAPH=true 后 rollout restart deployment/im" >&2
  exit 1
}

check_jpperf_k8s() {
  local pod=$1 pid=$2
  if kubectl exec -n "$NAMESPACE" "$pod" -- sh -c "tr '\\0' ' ' </proc/${pid}/cmdline" | grep -q 'JPperf'; then
    return 0
  fi
  echo "错误: Pod ${pod} 内 BEAM 未启用 +JPperf true。" >&2
  echo "  ConfigMap 设 IM_PERF_FLAMEGRAPH=true 后 rollout restart deployment/im" >&2
  exit 1
}

render_from_out_perf() {
  local work=$1
  (
    cd "$work"
    if [[ ! -s out.perf ]]; then
      echo "错误: out.perf 无样本。确认 BEAM 有 CPU 负载，且 perf 与 BEAM 同 UID。" >&2
      exit 1
    fi
    "${TOOLS}/stackcollapse-perf.pl" out.perf >out.folded
    "${TOOLS}/flamegraph.pl" --title "$TITLE" out.folded >flame.svg
    if [[ "$MERGE_SCHED" == "1" ]]; then
      sed -e 's/^[0-9]\+_//' -e 's/^erts_\([^_]\+\)_[0-9]\+/erts_\1/' out.folded >out.folded_sched
      "${TOOLS}/flamegraph.pl" --title "${TITLE} (schedulers merged)" out.folded_sched >flame_sched.svg
    fi
  )
}

start_load_k8s() {
  local pod=$1
  kubectl exec -n "$NAMESPACE" "$pod" -- /app/bin/im rpc \
    'Task.start(fn -> Enum.each(1..100_000_000, fn _ -> :rand.uniform() end) end)' \
    >/dev/null 2>&1 &
  echo $!
}

capture_local() {
  require_host_tools
  require_perf_local
  mkdir -p "$OUTPUT_DIR"
  local work="${OUTPUT_DIR}/run-local"
  rm -rf "$work"
  mkdir -p "$work"
  cd "$work"

  local pid event
  pid="$(beam_pid_local)"
  check_jpperf_local "$pid"
  if [[ -n "${PERF_EVENT:-}" ]]; then
    event="$PERF_EVENT"
  elif perf list hw 2>/dev/null | grep -qE '^\s+cycles(\s|$)'; then
    event="cycles:u"
  else
    event="cpu-clock:u"
  fi

  echo "[flamegraph] local perf record pid=${pid} event=${event} duration=${DURATION}s → ${work}"
  perf record -e "$event" -F 99 -p "$pid" --call-graph=fp -o perf.data -- sleep "$DURATION"
  perf script -i perf.data >out.perf

  render_from_out_perf "$work"
  echo "[flamegraph] 完成: ${work}/flame.svg"
  [[ "$MERGE_SCHED" == "1" ]] && echo "[flamegraph] 合并调度器: ${work}/flame_sched.svg"
}

capture_k8s() {
  require_host_tools
  local pod
  pod="$(resolve_pod)"
  if [[ -z "$pod" ]]; then
    echo "错误: 命名空间 ${NAMESPACE} 无 Running 的 im Pod" >&2
    exit 1
  fi
  require_perf_k8s "$pod"

  mkdir -p "$OUTPUT_DIR"
  local work="${OUTPUT_DIR}/run-k8s-${pod}"
  rm -rf "$work"
  mkdir -p "$work"

  local pid event remote_data="/tmp/im-perf.data" load_pid=""
  pid="$(beam_pid_k8s "$pod")"
  event="$(perf_event_in_pod "$pod")"
  check_jpperf_k8s "$pod" "$pid"

  if [[ "$GENERATE_LOAD" == "1" ]]; then
    load_pid="$(start_load_k8s "$pod")"
    sleep 1
  fi

  echo "[flamegraph] k8s perf record pod=${pod} pid=${pid} event=${event} duration=${DURATION}s"
  kubectl exec -n "$NAMESPACE" "$pod" -- sh -c \
    "exec perf record -e ${event} -F 99 -p ${pid} --call-graph=fp -o ${remote_data} -- sleep ${DURATION}"

  [[ -n "$load_pid" ]] && kill "$load_pid" 2>/dev/null || true

  kubectl cp "${NAMESPACE}/${pod}:${remote_data}" "${work}/perf.data"
  kubectl exec -n "$NAMESPACE" "$pod" -- perf script -i "$remote_data" >"${work}/out.perf"
  kubectl exec -n "$NAMESPACE" "$pod" -- rm -f "$remote_data"

  render_from_out_perf "$work"
  echo "[flamegraph] 完成: ${work}/flame.svg"
  [[ "$MERGE_SCHED" == "1" ]] && echo "[flamegraph] 合并调度器: ${work}/flame_sched.svg"
}

main() {
  case "${1:-$MODE}" in
    -h | --help) usage; exit 0 ;;
    local) capture_local ;;
    k8s) capture_k8s ;;
    *)
      echo "未知模式: $1" >&2
      usage
      exit 1
      ;;
  esac
}

main "$@"
