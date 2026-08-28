# Tasks: Phase 1 协议适配层

| 项 | 内容 |
| --- | --- |
| Spec | `phase-1-protocol-adapter` |
| Roadmap | P1-01 ~ P1-05 |
| 状态 | **已完成** |

勾选规则：完成并经测试验证后将 `- [ ]` 改为 `- [x]`。

---

## Task List

- [x] **1. P1-01 Codec**（依赖：无）
  - [x] 1.1 编写 `test/im/protocol/codec_test.exs`（合法 round-trip、错误 ver、损坏帧）
  - [x] 1.2 实现 `IM.Protocol.Codec`（`decode` / `encode` / `encode_payload` / `decode_payload`）
  - [x] 1.3 确认测试由红变绿

- [x] **2. P1-05 ErrorCodes（先于 Reply）**（依赖：无；与 Reply 耦合故提前）
  - [x] 2.1 编写 `test/im/protocol/error_codes_test.exs`
  - [x] 2.2 实现 `IM.Protocol.ErrorCodes`
  - [x] 2.3 烟雾测试锁定 `AuthResp` / `KickNotify` 关键字段

- [x] **3. P1-02 Reply**（依赖：2）
  - [x] 3.1 编写 `test/im/protocol/reply_test.exs`（seq/trace/cid、ref_cmd/ref_cid）
  - [x] 3.2 实现 `IM.Protocol.Reply.ok/3`、`success/3`、`error/2`
  - [x] 3.3 确认测试由红变绿

- [x] **4. P1-03 Push**（依赖：1）
  - [x] 4.1 编写 `test/im/protocol/push_test.exs`（seq=0、PUSH / PUSH_BATCH）
  - [x] 4.2 实现 `IM.Protocol.Push.build/3`
  - [x] 4.3 确认测试由红变绿

- [x] **5. P1-04 Router + Cmd**（依赖：无）
  - [x] 5.1 编写 `test/im/protocol/router_test.exs`（命中注入 handler、未注册、Cmd 互转）
  - [x] 5.2 实现 `IM.Protocol.Cmd` 与 `IM.Protocol.Router`
  - [x] 5.3 确认测试由红变绿

- [x] **6. 收尾**
  - [x] 6.1 `mise run test`（或至少 protocol 套件 + 既有测试）全绿
  - [x] 6.2 更新 `docs/implementation/elixir/PROGRESS.md` Phase 1 全部 `done`
  - [x] 6.3 本文件任务全部勾选

---

## Notes

- 一次按任务序号推进；不跨入 Phase 2。
- 公共 API 须 `@moduledoc` / `@doc`（中文 + `## 示例`）/ `@spec`。
- 不改 `proto/`（本 Phase 无需协议变更）。
