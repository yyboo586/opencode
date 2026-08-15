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
- 路径引用：使用 `file_path` + function name 格式
- 禁止使用 ```git stash/push``` 命令

## 3. 可用资源

- 用户级 skills / commands：`~/.config/opencode/skills/`、`~/.config/opencode/commands/`（实体目录，所有项目共享）
- **openspec 系列除外**：openspec skills/commands 不入全局，由各项目按需自装（`openspec update` 生成到项目 `.opencode/skills/` + `.opencode/command/opsx-*.md`，随 Git 归档）
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
| 索引 | `<cwd>/.opencode/MEMORY.md` | 中央索引 — Memory / Tracking 两节（内部结构见下「MEMORY.md 内部结构」；画像层在全局，见第 5 节） | `reference` | 经常变 |
| 记忆 | `<cwd>/.opencode/memory/` | 项目事实、模块业务逻辑、深度文档 | `reference` | 基本不变 |
| 任务 | `<cwd>/.opencode/tracking/` | 执行中/未完成任务专题 + 已完成的保留文档 + Q-A 经历记录 | `debug` / `design` / `analysis` | 经常变 |
| 画像 | `~/.config/opencode/me/` | 跨仓库用户画像（profile.md + advice.md） | `user` / `feedback` | 人不变即不变 |

### MEMORY.md 内部结构

- `## Memory — 项目事实与参考`：memory/ 文档索引
- `## Tracking — 进行中`：有**未闭环事项**的条目（进行中 / 待实测 / 待决策 / 待修复）
- `### 已处理/已归档`（Tracking 下三级标题）：**已闭环**条目（已修复 / 已回撤 / 已归档 / 已决策 / 已登记不处理），条目压缩为一行"已处理（日期，指向文档 + archive）"

**进行中/已处理判定**：条目存在未闭环事项 → 进行中；全部闭环 → 移入已处理小节（**移动，不删除**）。

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

- MEMORY.md「Tracking — 进行中」有未完成任务 → 读对应 tracking 专题续接（**仅相关专题**，不读全部）
- memory/ 深度文档 → 按索引定位 + 任务相关性按需展开

**不携带**：

- tracking/ 的 Q-A 归档与 memory/ 全文**不整体携带**进上下文（体量大、且大部分与当前任务无关）；需要时按索引定位检索
- "按需展开"≠"全部读取"：未命中任务相关性时，只读索引即可

### 更新规则（强制）

- 会话中形成新认知 / 任务有进展 → **即时更新** tracking/ 或 memory/，并同步 MEMORY.md 索引（不等会话结束）
- 会话结束时未完成任务**必须留在 tracking/**，且 MEMORY.md「Tracking」节保留摘要，保证下次会话可续接
- 任务完成后 **tracking 文档保留原地**，frontmatter `status` 标记完成状态（词表见下），同步更新 MEMORY.md 索引：条目从「Tracking — 进行中」**移到「已处理/已归档」小节并压缩为一行**"已修复（日期，指向文档 + archive）"；**不移入 memory/，不删除**——tracking 文档是分析过程（根因/实测证据/被否选项）的唯一载体，openspec archive 只记录"改了什么"不记录"为什么"
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

### openspec 内容纪律（与 .opencode 解耦）

**零引用**：openspec 文档（proposal / specs / design / tasks）禁止引用 `.opencode/` 任何路径（MEMORY.md / tracking/ / memory/）。依据：.opencode 对 Git 透明（不被追踪），而 openspec 随 Git 归档——引用会指向 Git 历史中不存在的文件，归档后即成死链。

**零操作**：openspec tasks 禁止包含 .opencode 维护动作（如"更新 MEMORY.md"、"写 tracking 文档"）；记忆维护由 AI 在 openspec 流程之外即时执行，不进入 change 任务清单。

**只含最终决策**：openspec design 的 Decisions 只写"采用了哪个方案 + 采纳依据"；被否决/对比方案（评估、权衡、否决理由、方案对比表）一律放对应 tracking 文档，不允许出现在 openspec 文档（含 proposal Why 背景、Non-Goals 措辞）。

**引用方向单向**：tracking 可引用 openspec（archive 作证据）；openspec 不得引用 tracking。

**完成态文档的后续修正**：追加 `### 更正 (YYYY-MM-DD)` 段说明修正内容与原因，**不覆盖原文**（与 q-a skill 修正模式一致）

### 沉淀管线

- `/q-a 整理`：蒸馏会话 → 项目 `.opencode/tracking/`（design/analysis/debug）
- `/update-profile`：从会话消息流提取画像证据 → 演进 `me/profile.md`（q-a 是显微镜，update-profile 是望远镜）

### Git 透明

- 四类文件/目录一律由 `.gitignore` 排除，**禁止 commit**；忽略规则建议放 `.opencode/.gitignore`（随目录复制即生效）
- 机制由本全局规则承载，仓库无需感知与重复描述

## 7. 结论与证据纪律（强制）

任何结论/断言必须附带**可复核的证据产物**；无法提供证据的断言一律视为"待验证"，不得以确定语气陈述。具体：

1. **存在性/影响面断言附搜索证据**：断言"0 引用 / 不存在 / 仅一处 / 无调用方"时，必须附实际执行的搜索命令 + 范围（须含 cmd/、test/、跨仓库引用）+ 命中结果。反例：清理提案称"0 调用方"漏搜 cmd/migrator → 返工。
2. **同类错误全量扫描**：发现 1 处错误后，同类模式必须全仓搜索并附命中清单（`file:line`）；清单外的同类命中属漏修。反例：ctx 共享反模式 19 处靠用户逐点发现。
3. **性能/兼容性/数据分布断言必须实测**：快/慢/可行/支持/占比类断言，必须附实测命令与输出（EXPLAIN/基准/语法验证/数据统计）；未实测的显式标注"未验证"。反例：假设方言语法支持 → 生产 SQL 报错；"路径不存在"→ 88.5% 数据证伪。
4. **代码改动与文档引用同步**：修改/删除代码后，必须搜索相关文档引用（契约注释 / README / MEMORY / design 等）并同步修正或登记，改动说明附引用核对结果。反例：删除方法后注释悬空、契约与实现矛盾存续多轮。
5. **并行审核独立性**：多审阅者并行审核时，每个审阅者 prompt 内联完整审核模板，禁止读取彼此报告。反例：B 审读 A 审报告 → 独立性打折，双审失去交叉验证价值。
6. **完成声明附可复核产物**：宣称"已记录 / 已完成 / 已写入"时必须附可复核产物（文件路径 + 条目/行号），无法给出即视为未执行，不宣称。反例：两次声明"已记入错题本"实际未写入，靠自查暴露。

## 7.5 操作纪律（强制）

1. **破坏性操作红线**：`rm` / `DROP` / `git checkout` / 删文件前，先 `git status` 确认跟踪状态 + 备份 + 征得用户同意；untracked 文件禁 `rm`（无恢复路径）；"删内容 vs 删文件"先确认。反例：2026-07-23 rm 未提交文件 → stash/reflog 全找不到，数据永久丢失。
2. **edit 前先 Read**：`oldString` 必须取自目标文件实际内容（含全角/缩进/行尾），失败后重读文件再重试，不凭记忆猜；identical 说明已是目标状态应跳过；multiple matches 加唯一上下文锚点。反例：全库 141+45+21 次 edit 失败，注释改中文 4 连败后仍宣称完成。

## 8. 规则自改进机制（强制流程）

从历史会话中提取"反复犯的错"，升格为硬规则，防止复发。**`/update-profile` 执行时自动附带执行**（见 update-profile skill Step 8）；也可独立触发（复盘批次 / 用户指令 / 同类错误重复出现——§7 第 2 条命中的模式）。

**流程**：

1. 会话提取（数据源见 update-profile skill Step 2a：opencode.db 直读 ro 或 opencode export）
2. 模式归纳：用户反复手工纠正的 / AI 结论被证伪的 / 同类错误复发的
3. 候选筛选：只保留**可核查产物**类条目（命令 / 清单 / 输出 / 条件字段），并用真实反例回测（事发当时能否拦截）
4. 候选清单交用户拍板（先列清单决策）
5. 按落层路由写入 + 记录对应关系（复盘文档 / MEMORY.md 索引）

**落层路由（全局 vs 本地，必须区分）**：

| 落点 | 判据 |
|------|------|
| 全局 `~/.config/opencode/AGENTS.md` | 跨项目通用的协作纪律——把规则放到另一个项目仍成立 |
| 项目 `<cwd>/AGENTS.md` | 依赖本仓库技术栈 / 历史 / 方言的约束 |
| `me/advice.md` | 人侧习惯类（AI 规则无法强制），同时把 advice 中与已升格规则重叠的条目收缩为引用 |
| 项目手册 / 复盘文档 | 一次性任务专属规则（不入常驻） |

**防膨胀约束（写入前自检）**：每条 ≤2 行 + 1 行真实反例；新增前 grep 检查是否已有规则覆盖；禁用行为词（认真 / 仔细 / 完整），只用产物名词；规则本身需过"看不懂"自检（对照规则增生教训）。

**依据**：2026-08-13 迁移复盘实践过一轮完整闭环（301 会话分析 → 7 条升格 → 全局/项目分层 → advice 收缩 → 对应关系记录），机制化后可反复执行。

## 9. 错题本机制（全局，跨会话错误传承）

两层文件（位置与 Git 归属见 `~/.config/opencode/README.md`）：

- **档案层** `mistakes.md`：错误**事件流**，允许重复（重复次数=升格信号），**不注入**上下文
- **注入层** `positive-rules.md`：正面指令**状态表**，每条唯一，经 `opencode.jsonc` 的 `instructions` 每次会话原生注入

**实时捕捉（强制）**——被用户纠正 / 自身假设被事实证伪 / 同坑复发时，当场执行：

1. `mistakes.md` 追加事件条目（日期/场景/错误做法/正确做法/状态）
2. `positive-rules.md` **先查可归并条目**：同场景/近义→合并更新；无法归并→新增一行（`场景: 正确做法`，必要时半句易错锚点）
3. 回复末尾附一行 `已记入错题本: <摘要>`；用户否决→回滚两处

**注入层自治（强制）**：`positive-rules.md` 是 AI 自主管理的精选指令集，**禁止平铺堆积**，人类不干涉其内容管理（唯一介入点是捕捉通知的否决权）：

- 每次写入先归并，无法归并才新增；随积累主动重组（合并同类、重排分类、压缩冗长、删除失效）
- 回顾时（`/update-profile` Step 9）补漏候选直接写入，无需拍板；仅 §8 硬规则升格候选交用户拍板

**skill 规则提取（第三个来源）**——自上而下通道：从 skill 内容提取**通用规则**到注入层，与实时捕捉/回顾扫描并列（触发：`/update-profile` Step 9 附带执行）：

1. **判据**：逐条审查 skill 的 CAUTION 块 / 强制规则 / 高频坑，问"这条规则是否会在**用户没提到该 skill 域**的任务中被违反？"——会 → 提取；不会（只有 skill 触发才涉及）→ 留在 skill
2. **格式**：提取条目附源标注 `(from <skill-name>)`，便于 skill 更新时按标注定位需同步的条目；归并逻辑与另两个来源统一（同场景合并，禁平铺）。**源标注必须回查 skill 原文确认存在**，与 skill 内容不符即视为伪证据并删除。反例：注入层 `(from go-tdd-workflow)` 假源标注（该 skill 无此内容），靠用户触发全局审计才暴露。
3. **边界**：提取**只写** positive-rules.md，**不改动** skill 原文（skill 保留完整知识，注入层只存通用触发子集）；skill 更新时按源标注回查同步

**格式纪律**：注入层每条一行、禁负面句式（"不要 X"→改写为"做 Y"）、超 ~100 行回顾时强制清理。
