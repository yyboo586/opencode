# opencode 全局配置目录

> **文档分工**：本文件存放**事实**（目录职责、工作区结构、资源布局）；`AGENTS.md` 只存放 **AI 行为约束**。约束归 AGENTS.md，事实归 README.md。
> 修改目录结构后，先同步本文件。

## 目录职责

| 条目 | 职责 | 版本管理 |
|------|------|---------|
| `AGENTS.md` | AI 行为约束（跨项目通用规则，所有项目生效） | git |
| `README.md` | 事实说明（本文件，目录结构唯一真相源） | git |
| `skills/` | 用户级技能（实体目录，所有项目共享；**openspec 系列除外**，见下） | git |
| `commands/` | 用户级命令（实体目录，所有项目共享；**openspec 系列除外**，见下） | git |
| `me/` | 开发者画像（profile.md + advice.md + insights/ + legacy-deployment/） | **gitignore，不入 git** |
| `mistakes.md` | 错题本档案层（错误事件流，可重复，不注入上下文） | git |
| `positive-rules.md` | 正面指令注入层（每条唯一，经 opencode.jsonc `instructions` 每次会话原生注入） | git |
| `opencode.jsonc` / `node_modules/` | opencode 运行时配置与依赖（`instructions` 字段引用 positive-rules.md） | 本地 |

> 2026-08-05 起 skills/commands 为实体目录（由原软链接改为实体），所有项目共用一份，无项目级副本。
>
> 2026-08-14 起 **openspec 系列除外**：openspec skills/commands 不入全局，由各项目按需自装（`openspec update` 生成到项目 `.opencode/skills/` + `.opencode/command/opsx-*.md`，随 Git 归档，见全局 AGENTS.md §3）。

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

- **用户画像及证据**（profile/advice/insight）一律存全局 `~/.config/opencode/me/`，不进入任何项目
- `node_modules/` + `package.json` 为 opencode 运行时产物（`@opencode-ai/plugin`），保留

### 记忆协同机制（事实）

> 行为约束见全局 `AGENTS.md` §6；此处仅记录归属与 Git 透明事实。

| 层 | 位置 | 归属 |
|----|------|------|
| 索引 `MEMORY.md` | 项目 `.opencode/` | 项目 |
| 记忆 `memory/` | 项目 `.opencode/` | 项目 |
| 任务 `tracking/` | 项目 `.opencode/` | 项目 |
| 画像 `me/` | 全局 `~/.config/opencode/` | 全局 |

- 项目记忆**永不进入全局仓库**；画像**永不进入项目**

### 错题本机制（事实）

> 行为约束见全局 `AGENTS.md` §9；此处仅记录归属与注入事实。

| 层 | 文件 | 内容 | 注入 |
|----|------|------|------|
| 档案层 | `mistakes.md` | 错误事件流（可重复，重复次数=升格信号） | 否 |
| 注入层 | `positive-rules.md` | 正面指令状态表（每条唯一） | 经 `opencode.jsonc` `instructions` 每次会话原生注入 |

- 捕捉：被纠正/假设证伪/同坑复发时实时双写（见 §9）
- 回顾：`/update-profile` Step 9 补漏扫描 + 去重压缩 + 复发≥2 次升格为 §8 硬规则
- **Git 透明**：四类文件/目录一律由 `.gitignore` 排除，不入 git。忽略规则放 `.opencode/.gitignore`：`MEMORY.md`、`me/`、`tracking/`、`memory/`
- 沉淀管线：`/q-a 整理`（tracking 归档 + 全局 `me/insights/` 画像证据）→ `/update-profile`（画像演进）

## 开发者画像

- 位置：`~/.config/opencode/me/`
- `profile.md`：开发者画像主文；`advice.md`：行为建议；`insights/`：q-a skill 产出的画像证据（update-profile 输入）；`legacy-deployment/`：历史旧版画像（参考保留）
- 画像内容跨仓库适用，由 `update-profile` skill 定期更新，**不入 git**
