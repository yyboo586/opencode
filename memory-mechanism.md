# 记忆协同机制（跨会话持久记忆）

> 本文件管"会话记忆存哪、怎么读写、什么能进什么不能进"，**不再全会话常驻注入**——按 AGENTS.md §1.4 触发：读写 `<cwd>/.opencode/` 前先读本文件。目录与工作区事实见 `README.md`。

## 四层记忆

| 层 | 位置 | 内容 | frontmatter type |
|----|------|------|------------------|
| 索引 | `<cwd>/.opencode/MEMORY.md` | Memory / Tracking 两节索引；Tracking 只放进行中 | `reference` |
| 归档 | `<cwd>/.opencode/archive/MEMORY-ARCHIVE.md` | 已闭环任务条目；只追加，文档不搬 | `reference` |
| 记忆 | `<cwd>/.opencode/memory/` | 项目是什么 / 怎么工作（深度事实，基本不变） | `reference` |
| 任务 | `<cwd>/.opencode/tracking/` | 正在做什么 / 做到哪了（任务专题 + Q-A 经历） | `debug` / `design` / `analysis` |

- **归属**：项目是什么/怎么工作 → `memory/`；正在做什么/做到哪了 → `tracking/`。
- **边界**：项目记忆只存项目 `.opencode/`，永不进全局仓库；全局仓库只承载机制规则、技能、命令。本机制由此处统一定义，各仓库 AGENTS.md 不重复书写。

## MEMORY.md 索引规则

- 结构：`## Memory — 项目事实与参考`（含历史文档索引）+ `## Tracking — 进行中`；闭环条目进 `archive/MEMORY-ARCHIVE.md`，不留在 Tracking。
- 条目只存**文档路径 + 1 行状态词**（如"进行中 / 待决策"）；禁止写结论、数据、摘要（差异数字、PID、命令、归因表、拍板依据都是文档内容）——细节去条目指向的文档里读。
- Tracking 只允许 active 状态：`进行中 / 待决策 / 待实测 / 待验证 / 待板测 / 待烟测 / 待执行 / 待用户审核` 等。`已闭环 / 已结案 / 已修复 / 已处理 / 已完成 / 已归档 / 已回撤` 必须移到 archive。
- archive 条目只允许闭环状态；格式 `- [标题](tracking/xxx.md) — 已闭环 YYYY-MM-DD`，文档仍留 `tracking/` 原址（避免断链）。
- Tracking 条目两种形态，按**是否含代码**判定（与内容类型无关）：无代码的分析/排障/设计 → 引 `tracking/` 文档；含代码的工程专项 → 引专项目录 `README.md`（子任务文档与代码同址）。
- 派生子任务不独立成条，挂总任务条目下作缩进子项（一句话状态 + 路径）；Memory 节同主题文档同样归并为总条目 + 子项。
- 判定与迁移：有未闭环事项 → 留在 Tracking；全部闭环 → 条目移入 Memory 节（**移动，不删除**；闭环子任务同理）。新增记忆文档时同步更新索引。

## 更新规则

- 形成新认知 / 任务有进展 → **即时**更新 tracking/ 或 memory/ 并同步索引，不等会话结束。
- 会话结束时未完成任务必须留在 tracking/，索引保留其路径，保证下次会话可续接。
- 任务完成：文档**保留原地** + frontmatter `status` 标完成；索引条目从 Tracking 移入 `archive/MEMORY-ARCHIVE.md`。**不删除、不默认移入 memory/**——未完成态下 tracking 文档是分析过程（根因/实测证据/被否选项）的唯一载体；仅"项目是什么/怎么工作"类深度事实才移入 memory/（例外动作，非默认）。
- 索引引用的文件路径变化 → 同步修正索引。

## tracking 文档约定

- **任务型**（排障/修复/分析，有生命周期）：frontmatter `type: debug|design|analysis` + `date` + `status` + `repo`。status 词表 `进行中 / 待实测 / 待决策 / 已修复 / 已回撤`（进行中可缺省，完成必须显式标注）。完成态示例：`status: 已修复（2026-08-12, c36d121, openspec archive: 2026-08-12-fix-mqtt-message-display）`
- **任务型写作模式（按 status 切换记录粒度）**：
  - **未完成**（`进行中 / 待实测 / 待决策`）：可记录落地明细、验证、反证、踩坑等过程——过程是下次会话续接的线索，不落盘则随会话消失。
  - **完成**（`已修复 / 已回撤`）：只保留决策与现状，不记落地明细、验证、反证、踩坑等中间过程；已写好的过程内容压缩为一行结论后删除。决策须含**采纳方案 + 被否方案及原因**（openspec 边界要求被否方案留 tracking，不能随过程删除）。新增内容以「决策行 + 日期」追加到对应阶段的决策节。缺陷编号不改号。
  - **重新打开**（status 改回进行中）：恢复过程记录模式，二次排障过程照常落盘。
- **经历型**（Q-A 会话蒸馏产出，无生命周期，写出即完成）：frontmatter `type` + `repo` + `tags` + `date`，不强制 status。
- 完成态文档的后续修正：追加 `### 更正 (YYYY-MM-DD)` 段说明修正内容与原因，**不覆盖原文**（适用于完成态留存内容：决策/现状）。

## 硬约束（确定性，不靠模型自觉）

- 单一实现：`session-viewer/cmd/memory-lint`（Go），规则见 `internal/memory`。插件、pre-commit、session-viewer 面板共用同一套判定。
- L1 提交门（可选）：仓库 `.githooks/pre-commit` 调用 `memory-lint --repo <root>`；Practice 当前不启用（2026-10-20 移除），提交前可手动跑 `memory-lint --repo .`。
- L2 写入门：全局插件 `plugins/memory-guard.ts` 按 `MEMORY.md` 文件 hash 比对，覆盖 edit/write/shell/execute 间接写；新增错误回滚并把违规列表返回给模型。
- 先开再清理：历史欠账写入 `.opencode/memory-lint-baseline.json`；默认只拦**新增**错误。清理后跑 `memory-lint --repo . --write-baseline` 收缩基线；`--strict` 忽略基线。
- 规则要点：条目一行 ≤300 字符、无子 bullet、链接必须存在且不得逃逸仓库、Tracking 只放 active、闭环进 archive、同一路径不得重复、tracking/memory 文档应有 frontmatter `type/date`。
- 跨仓引用纪律：md 链接只建在本仓库版本管理边界内（索引层由 `link_escape` 强制执行）；跨项目**不引用对方仓库的文档**——不做 md 链接、也不写对方文档路径（纯文本路径同样是耦合，会静默过时），定位粒度到"仓库名 + 领域/案例"为止，文档级定位由对方仓库的索引承担。适用于索引层与 tracking/memory/docs 正文。

## 与 openspec 的边界

- 路由：排查/根因分析/决策记录（无代码改动或未定案）→ `tracking/`；有代码改动的修复/特性 → openspec change 流程（proposal → specs → design → tasks → 实施 → archive）。
- 完成后 tracking 的 `status` 引用对应 openspec archive 作证据；openspec 记"改了什么"、tracking 记"为什么"，两者互补，不重复写修复细节。
- **openspec 零引用、零操作**：openspec 文档禁止引用 `.opencode/` 任何路径（记忆层文件可能被迁移/删除，引用会变死链，此纪律不因某仓库记忆层已入库而变）；openspec tasks 禁止包含记忆维护动作（"更新 MEMORY.md"、"写 tracking"等由 AI 在 change 流程外即时执行）。
- 引用方向单向：tracking 可引用 openspec，反向禁止。
- openspec design 的 Decisions 只写"采用哪个方案 + 采纳依据"；被否决方案、权衡对比一律放对应 tracking 文档（含 proposal Why、Non-Goals 措辞）。

## 与 README 的边界

- README.md 只放**静态事实**（目录结构/入口装配/构建命令/部署方式），随 Git 归档、面向外部读者；运行时机制（消息链路/数据流/业务逻辑/存储机制）只放 `.opencode/memory/`。
- README 禁止引用 `.opencode/` 路径（理由同上：死链风险）。
- 判定：内容需随项目分发（部署者/新接触者依赖）→ README；仅会话续接需要 → memory/。

## Git 透明

- 记忆层（MEMORY.md / archive/ / memory/ / tracking/）默认由 `.opencode/.gitignore` 排除（忽略规则放该文件，随目录复制即生效），**禁止 commit**。
- 例外：Practice 仓库记忆层随 Git 归档，其余仓库维持透明；归属事实见 README.md。
