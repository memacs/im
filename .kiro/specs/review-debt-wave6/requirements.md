# Requirements — Review Debt Wave6

## 目标

将审查还债 Wave1–5 已落地的实现写回 implementation 文档，消除「文档仍写 MVP/GenServer/未接 Oban」的漂移；顺带加固偶发失败的 DeviceLimit 测试。

## 需求

1. `permission-cache.md` / `message-send-ack.md` / `database.md`（TTL）/ `roadmap.md` 完成定义与代码对齐。
2. `DeviceLimitTest` 使用唯一 app/user，避免 Registry 串扰。
3. `PROGRESS.md` 标记 Wave6。

### 非目标

改业务逻辑；改 proto。
