# 文档与协议同步清单

| 项 | 内容 |
| --- | --- |
| 状态 | **活文档**（新增能力合入前必跑） |
| 来源 | 2026-07 阅后即焚（DD-036）纳入 v1 时的遗漏复盘 |
| 受众 | AI / 协作者；与 [`agent.md`](../../agent.md)「文档一致性」「协议为准」配套使用 |

---

## 1. 为什么会遗漏（根因）

阅后即焚首次合入时，**主路径文档已写**（`burn-after-read.md`、`proto`、`protocol.md` §26、`design-decisions`、`PROGRESS` P7-09），但仍有 **18+ 处**未同步。根因如下：

| # | 根因 | 表现 |
| --- | --- | --- |
| 1 | **只改「新文件 + 索引」** | 新建专题设计就以为完成，未按「能力在仓库里的所有落点」扫一遍 |
| 2 | **锚点过窄** | 对照撤回/编辑抄了主流程，但没 grep「撤回」「编辑」「400–499」等**已存在能力的所有引用** |
| 3 | **`agent.md` 工作流不完整** | 原流程列了 proto / protocol / 专题设计 / architecture-overview / implementation，**未列出**双通道、Kafka、cmd-type、system-design、auth 配置、可观测性、交叉引用等扇出点 |
| 4 | **总览表与明细不同步** | `PROGRESS` 任务行已更新，`roadmap` 阶段总览表、M5 里程碑仍写旧文案 |
| 5 | **横切关注点当可选** | `trace_id` 因果链、`AuthResp` 下发配置、`message_bodies` 字段、Kafka `im.downstream` 附录未视为必改项 |
| 6 | **实现文档只写新模块** | 有 `burn-after-read.md` impl，但未改**挂钩模块**（`read-receipt` 触发销毁、`message-send-ack` 发送校验） |
| 7 | **合入后未做全文检索验收** | 没有用关键词反查「还有没有只写撤回/编辑、没写新能力的地方」 |
| 8 | **合理例外与真遗漏混淆** | 群/室不支持阅后即焚**可以不写** group/room 专题，但 `dual-channel-api`、`system-design` 能力表仍须标明「单聊 only」 |

**教训**：本仓库文档是**网状引用**，不是「一个专题一个文件」。新增能力 = **主文档 + 全仓扇出 + grep 验收**。

---

## 2. 合入前必做（强制顺序）

与 [`agent.md`](../../agent.md)「修改协议工作流」叠加使用；**全部勾选**后方可标 `PROGRESS` done 或宣称「文档已同步」。

### 2.1 协议与决策（主路径）

- [ ] `proto/*.proto`（cmd、message、ErrorCode、AuthResp 等）
- [ ] `docs/design/protocol/protocol.md`（命令表、字段表、专节、错误码、测试 checklist）
- [ ] `docs/design/<module>.md`（**含 `## 完整流程` Mermaid**）
- [ ] `docs/design-decisions.md`（DD 编号 + 已确认一览 + protocol §）
- [ ] `docs/design/architecture-overview.md`（能力表、三种聊天对比、数据流若变）
- [ ] `docs/implementation/elixir/<module>.md`（模块、验收）
- [ ] `docs/implementation/elixir/PROGRESS.md` + `roadmap.md`（**任务行与阶段总览表、里程碑**）
- [ ] `mise run proto-check` 通过

### 2.2 命令字与封包

- [ ] `docs/design/cmd-type.md`（区间表 + 新区间说明节）
- [ ] `proto/common.proto` 注释与 `enum CmdType` 一致
- [ ] `agent.md`「命令字分区」一行
- [ ] `docs/design/packet.md`（若涉及错误模型 / trace；否则确认指向 proto 即可）

### 2.3 横切与基础设施

- [ ] `docs/design/dual-channel-api.md`（双通道能力表 + 仅 WS 例外）
- [ ] `docs/design/kafka-event-bus.md`（upstream/downstream 命令列举、附录映射表）
- [ ] `docs/design/message-context.md`（`trace_id` 须继承的 PUSH 类型）
- [ ] `docs/design/observability.md`（新埋点 / 指标 / Handler cmd）
- [ ] `docs/design/auth.md`（`AuthResp` / HTTP `config` 新字段）
- [ ] `docs/design/database/database-design.md`（表字段、`app_configs`、UPDATE 语义）

### 2.4 关联能力（交叉引用）

对**行为耦合**的已有模块，至少读一遍并更新决策表或交叉链接一行：

- [ ] `message-model.md`、`message-send-ack.md`
- [ ] `read-receipt.md`、`recall.md`、`edit.md`（互斥/触发关系）
- [ ] `offline-pull.md`、`reconnect.md`、`multi-device.md`
- [ ] `modular-architecture.md`（Router 复用示例）
- [ ] `system-design.md`（能力清单编号、会话差异表）
- [ ] `product-overview.md`、根 `README.md`、`docs/README.md`

### 2.5 实现挂钩（非仅新 impl 文件）

- [ ] 触发方 impl（例：阅后即焚 ← `read-receipt` impl 调 `BurnScheduler`）
- [ ] 入口方 impl（例：阅后即焚 ← `message-send-ack` 发送校验）
- [ ] `test-client.md` / Phase 10 回归范围（若适用）
- [ ] `web-console.md` Coverage 矩阵（新增/变更客户端可操作 cmd 时）
- [ ] `docs/design/README.md` 分类索引

### 2.6 Grep 验收（必跑）

在仓库根执行，**旧能力关键词仍单独出现且语义应包含新能力时** = 遗漏：

```bash
# 将 NEW 换成新能力中文/英文关键词，OLD 换成最相近已有能力（如阅后即焚 vs 撤回/编辑）
rg -n "撤回|编辑" docs/ proto/ README.md agent.md --glob '!**/burn-after-read.md'
```

针对**新能力专有词**反查是否已写入主路径：

```bash
rg -n "阅后即焚|burn_after_read|BURN_PUSH" docs/ proto/ README.md agent.md
```

期望：主路径与扇出文档均有命中；**不应**只在 1～2 个文件中出现。

针对 **cmd / 错误码**：

```bash
rg -n "400–499|400-499|CMD_MSG_.*403" docs/ proto/
# 新 cmd 应出现在 common.proto、protocol.md §4、cmd-type.md
```

---

## 3. 不必改的文件（合理例外）

| 情况 | 示例 |
| --- | --- |
| v1 明确不支持的能力域 | 阅后即焚不写 `group.md` / `room.md` 正文 |
| 仅描述已有能力的子场景 | 聊天室「短时缓存」只谈撤回/编辑 |
| 错误码枚举不重复 | `packet.md` 指向 `proto/common.proto` |
| 纯内部实现细节 | 某 `defp` 重命名 |

**但**：即使不支持，也须在 **protocol ChatType 表、system-design 会话差异表、dual-channel-api** 中写清「否 / v1 仅单聊」。

---

## 4. 案例：阅后即焚遗漏清单（归档）

以下为 2026-07 审核后补全的文件，供日后对照「扇出有多广」：

| 类别 | 曾遗漏文件 |
| --- | --- |
| 总览/索引 | `roadmap.md` 阶段表、M5；`README.md`、`docs/README.md` |
| 命令与协议 | `cmd-type.md` §3.6；`protocol.md` trace/ChatType/checklist |
| 横切 | `dual-channel-api.md`、`kafka-event-bus.md`、`auth.md`、`observability.md`、`message-context.md` |
| 数据与状态 | `database-design.md` 字段与 UPDATE 说明 |
| 系统设计 | `system-design.md`、`architecture-overview.md` §7 |
| 生命周期 | `offline-pull.md`、`reconnect.md`、`modular-architecture.md` §4.4 |
| 测试 | `test-client.md` |
| 实现挂钩 | `read-receipt.md`、`message-send-ack.md`（implementation） |

---

## 5. 维护

- 每次协议级能力合入后，若发现**新的一类扇出落点**，在本文件 §2 补一行。
- 不在此文件维护修订历史表；原因写在 PR / commit 说明即可。

---
