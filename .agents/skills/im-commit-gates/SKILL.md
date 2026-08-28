---
name: im-commit-gates
description: >-
  IM 仓库合入前门禁：format-check、全量 test、credo、proto 同步、文档一致性。
  用户要求提交/合入/PR 前检查、编写提交约束、或 Agent 准备 git commit 时使用。
auto_suggest: true
---

# IM 合入前门禁（Commit Gates）

**任何声称「可以提交 / 合入 / 标 done」之前，须本地跑通下列门禁。** 与 GHA [`.github/workflows/ci.yml`](../../../.github/workflows/ci.yml) 对齐。

---

## 强制清单（全部通过）

```text
合入门禁：
- [ ] mise run format-check          # mix format --check-formatted
- [ ] mise run im:credo              # 静态分析，零 issue
- [ ] mise run ci                    # proto + 严格编译 + audit + coveralls(≥80%) + 全仓 test
- [ ] 文档与代码一致、无矛盾（见下文）
- [ ] 协议/cmd 变更已完成 doc-sync（若适用）
- [ ] PROGRESS / architecture 已更新（若适用）
```

**禁止**：门禁未绿就 `git commit`。

---

## Git 提交规范

- **不要自动提交代码到 git**，需要进行确认
- **提交前必须让用户确认提交内容和 commit message**

### Agent 提交流程（强制）

1. **不得**在任务完成、测试通过、用户未开口时自动 `git commit`
2. 用户要求提交时，先输出 **待确认包**：
   - 变更文件列表（新增 / 修改 / 删除）
   - `git diff --stat` 或关键 diff 摘要
   - 建议的 **完整 commit message**（1–2 句，聚焦 why）
   - 合入门禁结果（format / credo / ci）
3. **等待用户明确确认**（可修改 message 或调整文件范围）
4. 确认后再执行 `git add` → `git commit`
5. **禁止**未经确认 `git push`

### 待确认包模板

```markdown
## 准备提交（请确认）

**变更文件**：
- `path/to/file.ex`（修改）
- …

**commit message**：
\`\`\`
feat: …
\`\`\`

**门禁**：format ✅ | credo ✅ | ci ✅

确认后我将执行提交；如需改 message 或排除文件请说明。
```

---

## 命令顺序（推荐）

由快到慢，失败即停：

```bash
mise run format-check      # 未过则 mise run format 后重跑
mise run im:credo
mise run proto-check       # ci 内含；单独改 proto 时先跑
mise run ci                # 等价 GHA：含 im_client、loadtest
```

轻量迭代（**不能代替合入前 `ci`**）：

```bash
mise run test              # 仅 IM + 当前 PGPORT
mise run im:compile-strict # 无 warning
```

阶段 2+ 行为变更另跑（见 [`im-implementation`](../im-implementation/SKILL.md) L4）：

```bash
mise run release-deploy && mise run release-smoke
```

---

## 各门禁说明

| 门禁 | 命令 | 失败时 |
| --- | --- | --- |
| **Format** | `format-check` | `mise run format`，勿手改缩进 |
| **Credo** | `im:credo` | 高优先级（warning+）零 issue；`mix credo --strict` 作逐步收紧 |
| **编译** | `ci` → `im:compile-strict` | 修 warning；禁止 `-warnings-as-errors` 绕过 |
| **依赖审计** | `ci` → `im:audit` | 升级/替换 retired hex 包 |
| **测试** | `ci` → `im:coveralls` 等 | 全量 test + **覆盖率 ≥80%**（`coveralls.json`）；禁止删断言过关 |
| **Proto 同步** | `proto-gen-check` | `mise run proto-gen` 后一并提交生成物 |

---

## 文档一致性（无矛盾）

代码与文档 **网状引用**，改一处须扫扇出点。

### 必守原则

1. **协议为准**：`proto/` + [`protocol.md`](../../../docs/design/protocol/protocol.md)；改语义须 **人工确认**
2. **文档不得互斥**：同一能力在 design / impl / README / agent 中描述须一致（能力边界、cmd、错误码、仅 WS 例外等）
3. **实现挂钩**：新能力须更新**触发方/入口方** impl 文档，非只写新专题文件
4. **活文档**：系统级变更更新 [`architecture-overview.md`](../../../docs/design/architecture-overview.md)；任务完成更新 [`PROGRESS.md`](../../../docs/implementation/elixir/PROGRESS.md)

### 合入前文档流程

按 **[`doc-sync-checklist.md`](../../../docs/design/doc-sync-checklist.md)**：

1. §2.1–§2.5 勾选适用项
2. §2.6 **grep 验收**（关键词反查遗漏）
3. 用 [`module-map.md`](../../../docs/module-map.md) 核对设计↔实现↔代码路径

### 常见矛盾（禁止）

| 矛盾 | 处理 |
| --- | --- |
| proto 有 cmd，protocol.md 无 | 补 protocol 命令表 |
| design 写支持，impl 写未实现 | 对齐 PROGRESS 状态或补实现 |
| REST 与 WS 能力表不一致 | 更新 `dual-channel-api.md` |
| 新 event/指标未登记 observability | 补 design + impl observability |
| `@doc` 与行为不符 | 以代码+protocol 为准修正文档 |

---

## TDD 与代码质量（合入前提）

见 [`AGENTS.md`](../../../AGENTS.md)：

- **测试先行**（非纯文档/部署任务）
- 公共 API：`@moduledoc`、`@doc`（**简体中文** + `## 示例`）、`@spec`
- 测试代码仅放 `test/support/`，禁止 test-only 进 `lib/`
- 生产日志经 `IM.Log`，禁止裸 `Logger.*`

---

## Agent 工作流

1. 完成实现后 **自行运行**上述门禁（不要只告诉用户去跑）
2. 失败 → 修复 → 重跑，直到全绿
3. 输出摘要：每条门禁 ✅/❌ + 关键失败原因
4. 文档变更列出：改了哪些 design/impl 文件、grep 是否已跑
5. **Git 提交规范**（见上文 §Git 提交规范）：不自动 commit；用户要求提交时先展示待确认包，**经确认后再 commit**

### 汇报模板（合入前，非提交）

```markdown
## 合入门禁

| 检查 | 结果 |
| --- | --- |
| format-check | ✅ |
| im:credo | ✅ |
| ci | ✅ |
| doc-sync | ✅（已 grep §2.6） |

**文档同步**：（列表或 N/A）

（若用户要求提交，另附 §Git 提交规范 的「待确认包」，勿在此直接 commit）
```

---

## 相关链接

- [`AGENTS.md`](../../../AGENTS.md) — TDD、规模前提、硬约束
- [`doc-sync-checklist.md`](../../../docs/design/doc-sync-checklist.md)
- [`im-implementation`](../im-implementation/SKILL.md) — 开发循环与 L0–L4
- [`.cursor/rules/commit-gates.mdc`](../../../.cursor/rules/commit-gates.mdc) — 会话级短规则
