# 记忆协同机制（跨会话持久记忆）

> 本机制解决：会话记忆存在哪、怎么读写、什么能进什么不能进。四层分工与流转全局统一，各仓库零重复描述。
> 本文件由全局 `AGENTS.md` 独立而来，经 `opencode.jsonc` `instructions` 每次会话注入。

## 四层记忆

| 层 | 位置 | 内容 | frontmatter type | 变化性 |
|----|------|------|------------------|--------|
| 索引 | `<cwd>/.opencode/MEMORY.md` | 中央索引 — Memory / Tracking 两节（内部结构见「每层怎么读写」；画像层在全局，见 AGENTS.md 第 4 节） | `reference` | 经常变 |
| 记忆 | `<cwd>/.opencode/memory/` | 项目事实、模块业务逻辑、深度文档 | `reference` | 基本不变 |
| 任务 | `<cwd>/.opencode/tracking/` | 执行中/未完成任务专题 + 已完成的保留文档 + Q-A 经历记录 | `debug` / `design` / `analysis` | 经常变 |
| 画像 | `~/.config/opencode/me/` | 跨仓库用户画像（profile.md + advice.md） | `user` / `feedback` | 人不变即不变 |

**内容归属判断**：

- 内容是"项目是什么 / 怎么工作" → `memory/`
- 内容是"正在做什么 / 做到哪了" → `tracking/`
- 内容是"我是谁 / 怎么协作" → `me/`

**边界铁律**：

- **项目相关记忆只存项目内 `.opencode/`**（MEMORY.md / memory/ / tracking/），**永不进入全局仓库**
- **全局仓库只承载**：机制规则（AGENTS.md + README.md）、全局技能（skills/）、全局命令（commands/）、开发者画像（me/）
- **画像（me/）只存全局** `~/.config/opencode/me/`，永不进入任何项目 `.opencode/`
- 记忆机制由本节省统一定义，各仓库 AGENTS.md 不需要重复书写

## 每层怎么读写

**MEMORY.md 内部结构**：

- `## Memory — 项目事实与参考`：memory/ 文档索引
- `## Tracking — 进行中`：有**未闭环事项**的条目（进行中 / 待实测 / 待决策 / 待修复）
- `### 已处理/已归档`（Tracking 下三级标题）：**已闭环**条目（已修复 / 已回撤 / 已归档 / 已决策 / 已登记不处理），按本节省条目规则只存路径；已处理/已归档与历史文档索引合并存于 `## Memory — 项目事实与参考` 节，不做独立小节（2026-08-20 起）

**索引条目只存文档路径（强制）**：MEMORY.md 所有条目（Memory / Tracking 进行中 / 已处理）只存**文档路径 + 1 行状态词**（如"待决策"、"已修复"、"已闭环"），**不存结论、不存数据、不存摘要**——任务是什么、结论是什么、细节是什么，全部去读条目指向的文档。反例（禁止）：索引里写差异数字、PID、命令、归因表、拍板依据；这些是文档内容，不是索引内容。

**进行中/已处理判定**：条目存在未闭环事项 → 进行中；全部闭环 → 移入已处理小节（**移动，不删除**）。

**Tracking 条目两种形态（强制，2026-08-21 起）**：`## Tracking — 进行中` 下的条目只允许两种形态，判定标准为**是否包含代码**（与内容类型无关）：

1. **形态 1：无代码的分析 / 排障 / 设计** → 引用 `.opencode/tracking/` 文档（如 `debug-log-list.md`、`design-device-number-auto-increment.md`）
2. **形态 2：含代码的工程专项** → 引用专项目录 README.md（如 `cmd/verify/README.md`，子任务文档与代码同址于该目录）

**派生子任务归并（嵌套条目，2026-08-21 起）**：派生于某总任务的子任务**不独立成条**，作为总任务条目的缩进子项（一句话状态 + 文档路径）；MEMORY.md 只记录总任务一句话状态 + 各子任务一句话状态，子任务细节看对应子任务文档；闭环子任务从 Tracking 移除（入 Memory 历史节）。嵌套形态同时适用于 `## Memory — 项目事实与参考` 历史节（同一主题的工具文档归并为一个总条目 + 缩进子项）。

新增记忆时同步更新 `MEMORY.md` 索引。

**读取时机（显式分层）**：

- **每次会话必读**：`<cwd>/.opencode/MEMORY.md` 索引（AGENTS.md 第 2 节第 4 步）— 小、经常变、起定位作用；`~/.config/opencode/me/profile.md` 画像（每次响应前，见 AGENTS.md 第 4 节）
- **条件读取**：MEMORY.md「Tracking — 进行中」有未完成任务 → 读对应 tracking 专题续接（**仅相关专题**，不读全部）；memory/ 深度文档 → 按索引定位 + 任务相关性按需展开
- **不携带**：tracking/ 的 Q-A 归档与 memory/ 全文**不整体携带**进上下文（体量大、且大部分与当前任务无关）；需要时按索引定位检索。"按需展开"≠"全部读取"：未命中任务相关性时，只读索引即可

**更新规则（强制）**：

- 会话中形成新认知 / 任务有进展 → **即时更新** tracking/ 或 memory/，并同步 MEMORY.md 索引（不等会话结束）
- 会话结束时未完成任务**必须留在 tracking/**，且 MEMORY.md「Tracking」节保留文档路径索引，保证下次会话可续接
- 任务完成后 **tracking 文档保留原地**，frontmatter `status` 标记完成状态（词表见下），同步更新 MEMORY.md 索引：条目从「Tracking — 进行中」**移入 `## Memory — 项目事实与参考` 节**（按本节省条目规则只存路径）；**不移入 memory/，不删除**——tracking 文档是分析过程（根因/实测证据/被否选项）的唯一载体，openspec archive 只记录"改了什么"不记录"为什么"
- **仅当**内容属"项目是什么 / 怎么工作"类深度事实（如迁移 tranche 记录、规范类文档）才移入 memory/——这是完成任务后的例外动作，不是默认动作
- 索引引用的文件路径变化时，同步修正 MEMORY.md

**tracking 文档约定**：

tracking/ 下文档分两类：

**1. 任务型（有生命周期）**：排障 / 修复 / 分析过程文档。

- frontmatter：`type: debug | design | analysis` + `date` + `status` + `repo`
- `status` 词表（完成必须显式标注，进行中可缺省）：`进行中` / `待实测` / `待决策` / `已修复` / `已回撤`
- 完成态示例：`status: 已修复（2026-08-12, c36d121, openspec archive: 2026-08-12-fix-mqtt-message-display）`
- 任务完成后：文档保留 + status 标记 + MEMORY.md 条目只存路径（移入 `## Memory — 项目事实与参考` 节）；**不删除、不移入 memory/**

**2. 经历型（q-a 产出）**：无任务生命周期（写出来即完成），按 q-a skill 格式（`type: debug|design|analysis` + `repo` + `tags` + `date`），**不强制 status**

**任务型 ↔ openspec 边界**：

- 排查 / 根因分析 / 决策记录（无代码改动或未定案）→ `.opencode/tracking/`
- 有代码改动的修复 / 特性 → **openspec change 流程**（proposal → specs → design → tasks → 实施 → archive）
- 完成后：tracking 文档 `status` 引用对应 openspec archive（不迁移、不重复写修复细节）；openspec archive 是修复证据，tracking 是分析过程，两者互补

## 边界纪律

**openspec 内容纪律（与 .opencode 解耦）**：

- **零引用**：openspec 文档（proposal / specs / design / tasks）禁止引用 `.opencode/` 任何路径（MEMORY.md / tracking/ / memory/）。大白话：tracking 文档可能被迁移/删除（先例：analysis-og-like-index.md 迁移 docs 后原件删除），即使记忆层随 Git 归档（Practice 特例，2026-08-18 起），引用仍可能变死链（指向不存在文件的链接）；且 openspec 只含最终决策、tracking 是分析过程载体，解耦纪律不因 Git 归属变化而变。
- **零操作**：openspec tasks 禁止包含 .opencode 维护动作（如"更新 MEMORY.md"、"写 tracking 文档"）；记忆维护由 AI 在 openspec 流程之外即时执行，不进入 change 任务清单。
- **只含最终决策**：openspec design 的 Decisions 只写"采用了哪个方案 + 采纳依据"；被否决/对比方案（评估、权衡、否决理由、方案对比表）一律放对应 tracking 文档，不允许出现在 openspec 文档（含 proposal Why 背景、Non-Goals 措辞）。
- **引用方向单向**：tracking 可引用 openspec（archive 作证据）；openspec 不得引用 tracking。
- **完成态文档的后续修正**：追加 `### 更正 (YYYY-MM-DD)` 段说明修正内容与原因，**不覆盖原文**（与 q-a skill 修正模式一致）

**Git 透明**：

- 四类文件/目录默认由 `.gitignore` 排除，**禁止 commit**；忽略规则建议放 `.opencode/.gitignore`（随目录复制即生效）
- **特例：Practice 仓库记忆层（MEMORY.md / memory/ / tracking/）随 Git 归档**（2026-08-18 起），其余仓库维持透明
- 机制由本全局规则承载，仓库无需感知与重复描述

**文档边界：README（随 Git 归档） vs .opencode（Git 透明）**：

- **README.md 只放静态事实**：目录结构 / 入口装配 / 构建命令 / 部署方式——随 Git 归档，面向任何读者（部署者/新接触者）。
- **运行时机制只放 `.opencode/memory/`**：消息链路 / 数据流 / 业务逻辑 / 存储机制——Git 透明，仅本地会话检索。
- **README 禁止引用 `.opencode/` 路径**（依据同 openspec 零引用：tracking 可能被迁移/删除，即使 Practice 记忆层已入库，引用仍可能变死链；.opencode 是会话续接材料，非分发内容）。
- **界限判定**：内容是否需要随项目分发？需要（部署者/新接触者依赖）→ README；仅会话续接需要 → `.opencode/memory/`。

## 沉淀管线

> 本机制解决：会话内容怎么变成知识文档。

- `/q-a 整理`：蒸馏（提炼精华）会话 → 项目 `.opencode/tracking/`（design/analysis/debug）
- `/update-profile`：从会话消息流提取画像证据 → 演进 `me/profile.md`（q-a 是显微镜——看单次会话细节；update-profile 是望远镜——看跨会话全局）
