# 压测长时间稳定性（LT-40）

配合 **P10-04**。目标环境跑满 **72h** 后归档报告；本地可用短时冒烟。

## 推荐命令

```bash
# 连接保活循环（示例 72h = 259200s；本地可先 600s）
DURATION_SEC=${DURATION_SEC:-259200}
END=$(( $(date +%s) + DURATION_SEC ))
ROUND=0
while [ "$(date +%s)" -lt "$END" ]; do
  ROUND=$((ROUND + 1))
  mise run loadtest:run -- connection_load \
    --app-key "$APP_KEY" \
    --users "${USERS:-50}" \
    --concurrency "${CONCURRENCY:-25}" \
    --report "tmp/soak-connection-$ROUND.json" || true
  mise run loadtest:run -- message_flood \
    --app-key "$APP_KEY" \
    --users "${USERS:-20}" \
    --iterations "${ITERATIONS:-20}" \
    --report "tmp/soak-flood-$ROUND.json" || true
  sleep "${SLEEP_SEC:-300}"
done
```

或使用仓库脚本：`scripts/loadtest-soak.sh`。

## 验收关注

- 进程无泄漏：BEAM memory / connection 数稳定
- 错误率：`worker_results.error / total` 趋近 0
- P99：见 `loadtest-report.md` 模板字段
- 故障演练穿插：见 `fault-drill.md`

## 报告

将最终 JSON 与环境说明填入 `docs/implementation/elixir/loadtest-report.md`。
