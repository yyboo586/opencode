# opencode 全局配置目录

> **文档分工**：本文件存放**事实**（目录职责、工作区结构、资源布局）；`AGENTS.md` 只存放 **AI 行为约束**。约束归 AGENTS.md，事实归 README.md。
> 修改目录结构后，先同步本文件。

## 目录职责

| 条目 | 职责 | 版本管理 |
|------|------|---------|
| `AGENTS.md` | AI 行为约束（跨项目通用规则，所有项目生效） | git |
| `memory-mechanism.md` | 记忆协同机制全文（不再常驻注入；AGENTS.md §1.4 触发，读写记忆前按需读） | git |
| `README.md` | 事实说明（本文件，目录结构唯一真相源） | git |
| `skills/` | 用户级技能（实体目录，所有项目共享；**openspec 系列除外**，见下） | git |
| `commands/` | 用户级命令（实体目录，所有项目共享；**openspec 系列除外**，见下） | git |
| `plugins/` | 本地插件（memory-sync / notify / system-prompt-logger / tool-stats，单文件双兼容 v1/v2；支撑目录：`kdco-primitives/`（`index.ts` 已改名禁用）、`notify/`、`tool-stats/`（报表 + 文档 + 历史脚本）） | git |
| `tsconfig.json` | 编辑器类型检查（插件 .ts 用；依赖 devDependencies 的 `@types/node`、`@types/bun`，`npm i` 维护） | git |
| `opencode.jsonc` / `node_modules/` | opencode 运行时配置与依赖（原 plugins 数组项已本地化为 `plugins/system-prompt-logger.ts`） | 本地 |

> 2026-08-05 起 skills/commands 为实体目录（由原软链接改为实体），所有项目共用一份，无项目级副本。
>
> 2026-08-14 起 **openspec 系列除外**：openspec skills/commands 不入全局，由各项目按需自装（`openspec update` 生成到项目 `.opencode/skills/` + `.opencode/command/opsx-*.md`，随 Git 归档）。

## 工作区结构

工作区根按环境自动适配，AI 启动时按以下顺序 `ls` 探测，取首个存在的：

- Linux 原生：`~/platform/`
- WSL：`/mnt/d/platform/`

| 仓库 | 作用 |
|------|------|
| Practice | 知识库（Go / 网络 / 数据库 / 中间件 / Docker / Nacos） |
| rbEdgeServer | 边缘网关 Go 服务 |
| rbiotserver | IoT Go 服务 |
| rblogserver | 日志 Go 服务 |
| Deployment | 固件打包工具 |
| nps | 内网穿透 |
| tsl / visualdevice / log / licenses / phpstudy_pro | 辅助项目 / 工具 |

## 子项目 `.opencode` 目录约定

每个工作区子项目的 `.opencode/` **只保存**：

| 条目 | 内容 |
|------|------|
| `MEMORY.md` | 跨会话持久记忆索引 |
| `memory/` | 学习参考知识 + 深度文档 |
| `tracking/` | Q-A 会话记录（knowledge/design/analysis/debug 类型） |

排除项：

- `node_modules/` + `package.json` 为 opencode 运行时产物（`@opencode-ai/plugin`），保留

### 记忆协同机制（事实）

> 行为约束见 `memory-mechanism.md`；此处仅记录归属与 Git 透明事实。

| 层 | 位置 | 归属 |
|----|------|------|
| 索引 `MEMORY.md` | 项目 `.opencode/` | 项目 |
| 记忆 `memory/` | 项目 `.opencode/` | 项目 |
| 任务 `tracking/` | 项目 `.opencode/` | 项目 |

- 项目记忆**永不进入全局仓库**

- **Git 透明（默认）**：三类文件/目录一律由 `.gitignore` 排除，不入 git。忽略规则放 `.opencode/.gitignore`：`MEMORY.md`、`tracking/`、`memory/`
- **特例：Practice 仓库记忆层（MEMORY.md / memory/ / tracking/）随 Git 归档**（2026-08-18 起），其余仓库维持透明
