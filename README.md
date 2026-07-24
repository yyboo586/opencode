# opencode 全局配置目录

> **文档分工**：本文件存放**事实**（目录职责、工作区结构、资源布局）；`AGENTS.md` 只存放 **AI 行为约束**。约束归 AGENTS.md，事实归 README.md。
> 修改目录结构后，先同步本文件。

## 目录职责

| 条目 | 职责 | 版本管理 |
|------|------|---------|
| `AGENTS.md` | AI 行为约束（跨项目通用规则，所有项目生效） | git |
| `README.md` | 事实说明（本文件，目录结构唯一真相源） | git |
| `skills/` | 用户级技能（实体目录，所有项目共享） | git |
| `commands/` | 用户级命令（实体目录，所有项目共享） | git |
| `me/` | 开发者画像（profile.md + advice.md + insights/ + legacy-deployment/） | **gitignore，不入 git** |
| `opencode.jsonc` / `node_modules/` | opencode 运行时配置与依赖 | 本地 |

> 2026-08-05 起 skills/commands 为实体目录（由原软链接改为实体），所有项目共用一份，无项目级副本。

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

## 开发者画像

- 位置：`~/.config/opencode/me/`
- `profile.md`：开发者画像主文；`advice.md`：行为建议；`insights/`：q-a skill 产出的画像证据（update-profile 输入）；`legacy-deployment/`：历史旧版画像（参考保留）
- 画像内容跨仓库适用，由 `update-profile` skill 定期更新，**不入 git**
