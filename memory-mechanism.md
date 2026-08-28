# 记忆协同机制（跨会话持久记忆）

> 本机制解决：会话记忆存在哪、怎么读写、什么能进什么不能进。四层分工与流转全局统一，各仓库零重复描述。
> 本文件由全局 `AGENTS.md` 独立而来，经 `opencode.jsonc` `instructions` 每次会话注入。

## 四层记忆

| 层 | 位置 | 内容 | frontmatter type | 变化性 |
|----|------|------|------------------|--------|
| 索引 | `<cwd>/.opencode/MEMORY.md` | 中央索引 — Memory / Tracking 两节 | `reference` | 经常变 |
| 记忆 | `<cwd>/.opencode/memory/` | 项目事实、模块业务逻辑、深度文档 | `reference` | 基本不变 |
| 任务 | `<cwd>/.opencode/tracking/` | 执行中/未完成任务专题 + 已完成的保留文档 + Q-A 经历记录 | `debug` / `design` / `analysis` | 经常变 |
| 画像 | `~/.config/opencode/me/` | 跨仓库用户画像（核心在 AGENTS.md §2，完整留档 profile.md + advice.md） | `user` / `feedback` | 人不变即不变 |

**内容归属**：项目是什么/怎么工作 → `memory/`；正在做什么/做到哪了 → `tracking/`；我是谁/怎么协作 → `me/`。

**边界铁律**：

- 项目相关记忆只存项目内 `.opencode/`，**永不进入全局仓库**；画像（me/）只存全局，**永不进入任何项目**
- 全局仓库只承载：通用机制规则（AGENTS.md + memory-mechanism.md）、全局技能（skills/）、全局命令（commands/）、开发者画像（me/）
- 记忆机制由本节省统一定义，各仓库 AGENTS.md 不需要重复书写

## 每层怎么读写

**MEMORY.md 内部结构**：`## Memory — 项目事实与参考`（memory/ 文档索引，含已处理/已归档条目，2026-08-20 起不做独立小节）；`## Tracking — 进行中`（有未闭环事项的条目）。

**索引条目只存文档路径（强制）**：所有条目只存**文档路径 + 1 行状态词**，不存结论、数据、摘要；任务与结论全部去读条目指向的文档。

**Tracking 条目一种形态（强制）**：MEMORY.md 统一引用 `.opencode/tracking/` 文档，不论追踪内容是否包含可运行代码（如 rbiotserver `Mongo-openGauss迁移验证.md`——含 ETL/验证脚本的工程专项同样以 tracking 文档承载；代码位置在 tracking 文档内说明即可）。

**派生子任务归并**：子任务不独立成条，作为总任务条目的缩进子项（一句话状态 + 文档路径）；同样适用于 Memory 历史节。

**读取时机（显式分层）**：

- **每次会话必读**：`<cwd>/.opencode/MEMORY.md` 索引（小、经常变、起定位作用）；画像核心已注入（AGENTS.md §2），完整画像按需查
- **条件读取**：MEMORY.md「Tracking — 进行中」有未完成任务 → 读对应 tracking 专题续接（仅相关专题，不读全部）；memory/ 深度文档 → 按索引定位 + 任务相关性按需展开
- **不携带**：tracking/ 的 Q-A 归档与 memory/ 全文不整体携带进上下文；"按需展开"≠"全部读取"

**更新规则（用户驱动，2026-08-26 起）**：

- **不自动更新**：会话中形成新认知 / 任务有进展，AI 不主动写 tracking/ 或 memory/，不主动同步 MEMORY.md 索引
- **仅用户显式要求会话整理时更新**（如 `/q-a`）：根据会话内容与既有 tracking 文档的相关性判断，**相关才更新**对应 tracking 文档并同步 MEMORY.md 索引
- **tracking 文档的进行中 / 已归档 / 删除由用户手动处理，AI 不自动流转**
- 沉淀管线：`/q-a 整理`（tracking 归档 + 全局 `me/insights/` 画像证据）→ `/update-profile`（画像演进）
- 索引引用的文件路径变化时，同步修正 MEMORY.md

## 边界纪律

**Git 透明**：

- 四类文件/目录默认由 `.gitignore` 排除，**禁止 commit**；忽略规则建议放 `.opencode/.gitignore`（随目录复制即生效）
- **特例：Practice 仓库记忆层（MEMORY.md / memory/ / tracking/）随 Git 归档**（2026-08-18 起），其余仓库维持透明
- 机制由本全局规则承载，仓库无需感知与重复描述