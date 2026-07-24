---
name: git-commit
description: 仅根据 git diff --cached（暂存区）生成中文 Conventional Commits 格式提交信息，忽略未暂存变更。触发：提交代码 / commit / 生成 commit / 写 commit。禁止 push。
---

# git-commit — 中文 Conventional Commits 提交信息生成

## 安全规则（强制）

1. **禁止 `git push`**——本 skill 只做本地提交，不推送远程
2. **必须用户确认**——展示候选 message 后等待 `y/e/r/n`，不自动 commit
3. **禁止不可逆操作**——`git reset --hard` / `git clean -fd` / `git push --force` 等

## 触发条件

用户表达以下意图时激活：
- "提交代码" / "commit" / "写 commit" / "生成 commit 信息"
- "提交一下" / "帮我提交" / "看看改了什么，帮我提交"

## 工作流

### Step 1：检查环境

```bash
git rev-parse --is-inside-work-tree   # 确认在 Git 仓库内
```

非 0 退出码：终止，提示"当前目录不是 Git 仓库"。

### Step 2：检查暂存区

```bash
git diff --cached --quiet; echo $?    # 0 = 无暂存，非 0 = 有暂存
```

- 有暂存：继续 Step 3
- 无暂存：提示用户 `git add <files>` 或 `git add .`，等用户确认后再继续

### Step 3：读取变更

```bash
git diff --cached --stat              # 变更概览（人类可读）
git diff --cached                     # 完整 diff（用于生成 message）
```

### Step 4：生成候选 message

#### Step 4.1：判断 commit 结构

一次 commit 能不能用一行说清？

- **能** → 单一改动：只写 subject，不写 body
- **不能**（多文件/多领域）→ 混合 commit：subject 概括目标 + body 列 facets

混合 commit 的 subject 写"改了什么 / 为什么要改"，不罗列具体文件或改动项——那是 body 的事。

#### Step 4.2：subject 格式

```
type(scope): 中文描述
```

- `type` 必选，scope 可选
- 中文描述不超过 50 字，简洁准确
- **单一改动**：描述 = 改动本身
- **混合 commit**：描述 = 概括目标（改了什么 / 为什么改），不罗列具体文件
- 多个 type 选最主要的

#### Step 4.3：body 格式（仅混合 commit 需要）

混合 commit 必须接 body，否则 subject 信息密度过低：

```
- type(scope): facet 描述
- type(scope): facet 描述
- ...
```

- 每个 facet 必须带 type 前缀
- facet 描述同样不超过 50 字
- body 与 subject 之间空一行
- **不写重复 subject 的铺陈**——body 直奔 facets。仅当 facets 之间的关联不够自明时（如跨多个无关目录、历史包袱说明），才在 bullets 前加 1 句衔接背景

#### type 枚举

| type | 含义 | 例子 |
|------|------|------|
| `feat` | 新功能 | 新增接口底层结构专题 |
| `fix` | 修复 Bug | 修复 Q-A skill 误删问题 |
| `docs` | 文档变更 | 更新 Q-A 治理规范 |
| `refactor` | 重构（非新功能非修复） | 删除子专题 INDEX.md |
| `perf` | 性能优化 | 优化管道读写路径 |
| `test` | 添加或修改测试 | 补齐 ifacetype 测试 |
| `build` | 构建系统或依赖变更 | 升级 Go 版本到 1.21 |
| `ci` | CI 配置变更 | 调整 GitHub Actions |
| `chore` | 其他不修改 src/test 的变更 | 更新 AGENTS.md 规则 |
| `revert` | 回退提交 | revert 上次错误提交 |

#### scope 推断

按文件路径顶级目录或包名推断 scope，跨 3+ 个目录归 `chore`。根据实际 diff 中的文件路径自行判断，不硬编码路径映射表。

### Step 5：展示 + 确认

#### 单一改动示例

```
本次变更：
  src/auth/login.go   (新增 45 行)

候选 commit message:
  feat(auth): 新增登录接口

确认？[y/e/r/n] (y=yes, e=edit, r=retry, n=abort):
```

#### 混合 commit 示例

```
本次变更：
  storage/storage.go                            (+12 -3, 修复 Seek 错误处理)
  forward/forward.go, worker/writestoragejob.go (加 ctx 超时)
  storage/helper_test.go, storage_test.go       (requireDB 取代 skipIfShortOrNoDB)
  Makefile, build.sh, .golangci.yml             (构建链升级)
  .claude/skills/rbedge-build-test/SKILL.md     (新增 skill)
  openspec/changes/archive/...                  (归档 2 个 change)

候选 commit message:
  refactor(storage): openGauss 迁移治理收尾

  - fix(storage): position 文件 Seek 错误显式处理，避免幽灵推进
  - refactor(forward/worker): storage 读写加 5s/10s ctx 超时兜底
  - test(storage): requireDB 取代 skipIfShortOrNoDB，杜绝静默 skip 假绿
  - build: Makefile 精简 + build.sh 默认 arm64 + 接入 golangci-lint
  - docs: 新增 rbedge-build-test skill + 归档 executor-spec/cleanup-session

确认？[y/e/r/n] (y=yes, e=edit, r=retry, n=abort):
```

- `y`：执行 `git commit -m "候选 message"`
- `e`：用户编辑后再次确认
- `r`：重新生成（基于调整提示）
- `n`：取消，不执行

### Step 6（可选）：amend 模式

若用户说"修改上次 commit" / "amend"：

1. 先展示上次 commit message
2. 生成新 message
3. 等用户确认 → `git commit --amend -m "新 message"`

## 注意事项

- diff 过大（> 1000 行）时，关注核心变更逻辑，忽略 lock 文件、生成代码
- **混合 commit 的 subject 概括目标**，不罗列文件/目录；跨多个无关领域时建议拆 commit
- 涉及多个领域且无明显主题时归 `chore`
- 用户在 commit 信息中要求"撤回"或"reset"——拒绝并提示手工操作
- **只看暂存区**：所有变更读取均基于 `git diff --cached`，绝不读取或考虑未暂存的变更（unstaged changes）
