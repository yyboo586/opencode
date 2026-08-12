# OpenCode 全局 AI 协作规则（用户级 ~/.config/opencode/AGENTS.md）

本文件位于 `~/.config/opencode/AGENTS.md`，对所有项目生效。
项目级规则以 `<cwd>/AGENTS.md` 为准；冲突时以更具体的（项目级）为准。

> 目录结构、工作区布局、资源位置等**事实**见同目录 `README.md`；本文件只放行为约束。

## 1. 跨仓库引用约定（强约定）

当用户或 AI 在工作区内提到"去 xx 仓库"、"看 xx 仓库的代码"时：

- AI 自动拼路径：`<工作区根>/<仓库名>/`（工作区根按 README.md 探测结果）
- **禁止**输出"当前仓库同级目录 xx"、"../xx"、绝对长路径等冗余表述
- 用户表达保持简洁，AI 内部按工作区根解析

> 触发此约定的关键词：去 / 看 / 查 / 打开 / 读 / 搜索 + 仓库名（或常识中能识别的仓库缩写）

## 2. 全局行为规范

- 用中文交互。
- 任务启动顺序：
  1. 读本文件（全局规则）
  2. 读 `~/.config/opencode/README.md`（目录事实，如需定位资源）
  3. 读 `<cwd>/AGENTS.md`（项目级规则）
  4. 读 `<cwd>/.opencode/MEMORY.md`（项目持久记忆索引，如存在；机制见第 6 节）
  5. 若 MEMORY.md「Tracking」节有未完成任务 → 读对应 `.opencode/tracking/` 专题文件续接
  6. 再开始行动
- 多文件操作：并行调用 Read / Grep / Glob / Bash
- 路径引用：使用 `file_path:line_number` 格式
- 质问用户：是否把简单的问题复杂化了？

- 禁止使用 ```git commit``` 命令
- 禁止使用 ```git stash/push``` 命令

## 3. 可用资源

- 用户级 skills / commands：`~/.config/opencode/skills/`、`~/.config/opencode/commands/`（实体目录，所有项目共享）
- 遇到匹配 skill 描述的任务，**必须先加载 skill** 再行动

## 4. 规则覆盖范围（边界）

本文件**只放**全局通用规则。下列内容**不放**在本文件：

- 仓库内部工作流（如 Practice 的 openspec 流程）
- 仓库专属持久记忆（由 `<cwd>/.opencode/MEMORY.md` 承担）
- 具体技术栈约定（如 Go 测试模式、数据库方言适配）

## 5. 开发者画像

跨仓库行为特征维护在 `~/.config/opencode/me/profile.md`，由 `update-profile` skill 定期更新。
画像内容跨仓库适用——编码风格、沟通偏好、思维模式、学习方式等特征不因项目而异。

Before responding, read `~/.config/opencode/me/profile.md` to understand the developer's coding habits and preferences.

## 6. 记忆协同机制（跨会话持久记忆）

四层记忆分工与流转，机制全局统一、各仓库零重复描述。

### 边界铁律

- **项目相关记忆只存项目内 `.opencode/`**（MEMORY.md / memory/ / tracking/），**永不进入全局仓库**
- **全局仓库只承载**：机制规则（本文件 + README.md）、全局技能（skills/）、全局命令（commands/）、开发者画像（me/）
- **画像（me/）只存全局** `~/.config/opencode/me/`，永不进入任何项目 `.opencode/`
- 记忆机制由本节省统一定义，各仓库 AGENTS.md 不需要重复书写

### 四层结构

| 层 | 位置 | 内容 | frontmatter type | 变化性 |
|----|------|------|------------------|--------|
| 索引 | `<cwd>/.opencode/MEMORY.md` | 中央索引 — Tracking / Memory 两节（画像层在全局，见第 5 节） | `reference` | 经常变 |
| 记忆 | `<cwd>/.opencode/memory/` | 项目事实、模块业务逻辑、深度文档 | `reference` | 基本不变 |
| 任务 | `<cwd>/.opencode/tracking/` | 执行中/未完成任务专题 + 已完成的保留文档 + Q-A 经历记录 | `debug` / `design` / `analysis` | 经常变 |
| 画像 | `~/.config/opencode/me/` | 跨仓库用户画像（profile.md + advice.md） | `user` / `feedback` | 人不变即不变 |

**判断标准**：

- 内容是"项目是什么 / 怎么工作" → `memory/`
- 内容是"正在做什么 / 做到哪了" → `tracking/`
- 内容是"我是谁 / 怎么协作" → `me/`

新增记忆时同步更新 `MEMORY.md` 索引。

### 读取时机（显式分层）

**每次会话必读**：

- `<cwd>/.opencode/MEMORY.md` 索引（第 2 节第 4 步）— 小、经常变、起定位作用
- `~/.config/opencode/me/profile.md` 画像（每次响应前，见第 5 节）

**条件读取**：

- MEMORY.md「Tracking」节有未完成任务 → 读对应 tracking 专题续接（**仅相关专题**，不读全部）
- memory/ 深度文档 → 按索引定位 + 任务相关性按需展开

**不携带**：

- tracking/ 的 Q-A 归档与 memory/ 全文**不整体携带**进上下文（体量大、且大部分与当前任务无关）；需要时按索引定位检索
- "按需展开"≠"全部读取"：未命中任务相关性时，只读索引即可

### 更新规则（强制）

- 会话中形成新认知 / 任务有进展 → **即时更新** tracking/ 或 memory/，并同步 MEMORY.md 索引（不等会话结束）
- 会话结束时未完成任务**必须留在 tracking/**，且 MEMORY.md「Tracking」节保留摘要，保证下次会话可续接
- 任务完成后 **tracking 文档保留原地**，frontmatter `status` 标记完成状态（词表见下），同步更新 MEMORY.md 索引（条目压缩为一行"已修复（日期，指向文档 + archive）"）；**不移入 memory/，不删除**——tracking 文档是分析过程（根因/实测证据/被否选项）的唯一载体，openspec archive 只记录"改了什么"不记录"为什么"
- **仅当**内容属"项目是什么 / 怎么工作"类深度事实（如迁移 tranche 记录、规范类文档）才移入 memory/——这是完成任务后的例外动作，不是默认动作
- 索引引用的文件路径变化时，同步修正 MEMORY.md

### tracking 文档约定

tracking/ 下文档分两类：

**1. 任务型（有生命周期）**：排障 / 修复 / 分析过程文档。

- frontmatter：`type: debug | design | analysis` + `date` + `status` + `repo`
- `status` 词表（完成必须显式标注，进行中可缺省）：`进行中` / `待实测` / `待决策` / `已修复` / `已回撤`
- 完成态示例：`status: 已修复（2026-08-12, c36d121, openspec archive: 2026-08-12-fix-mqtt-message-display）`
- 任务完成后：文档保留 + status 标记 + MEMORY.md 条目压缩为一行；**不删除、不移入 memory/**

**2. 经历型（q-a 产出）**：无任务生命周期（写出来即完成），按 q-a skill 格式（`type: debug|design|analysis` + `repo` + `tags` + `date`），**不强制 status**

**任务型 ↔ openspec 边界**：

- 排查 / 根因分析 / 决策记录（无代码改动或未定案）→ `.opencode/tracking/`
- 有代码改动的修复 / 特性 → **openspec change 流程**（proposal → specs → design → tasks → 实施 → archive）
- 完成后：tracking 文档 `status` 引用对应 openspec archive（不迁移、不重复写修复细节）；openspec archive 是修复证据，tracking 是分析过程，两者互补

**完成态文档的后续修正**：追加 `### 更正 (YYYY-MM-DD)` 段说明修正内容与原因，**不覆盖原文**（与 q-a skill 修正模式一致）

### 沉淀管线

- `/q-a 整理`：蒸馏会话 → 项目 `.opencode/tracking/`（design/analysis/debug）
- `/update-profile`：从会话消息流提取画像证据 → 演进 `me/profile.md`（q-a 是显微镜，update-profile 是望远镜）

### Git 透明

- 四类文件/目录一律由 `.gitignore` 排除，**禁止 commit**；忽略规则建议放 `.opencode/.gitignore`（随目录复制即生效）
- 机制由本全局规则承载，仓库无需感知与重复描述
