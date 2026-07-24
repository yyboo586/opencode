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
  4. 读 `<cwd>/.opencode/MEMORY.md`（项目持久记忆，如存在）
  5. 再开始行动
- 多文件操作：并行调用 Read / Grep / Glob / Bash
- 路径引用：使用 `file_path:line_number` 格式

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
