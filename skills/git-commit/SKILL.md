---
name: git-commit
description: 仅根据 git diff --cached（暂存区）生成中文 Conventional Commits 格式提交信息，忽略未暂存变更；message 必含版本号，暂存含代码变更而版本未升时默认 minor+1（确认后自动改版本文件）。触发：提交代码 / commit / 生成 commit / 写 commit。禁止 push。
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

### Step 3.5：版本检查（强制，在生成 message 之前）

message 必须携带版本号，且**代码变更必须伴随版本升级**。流程：

#### a. 豁免判定

暂存 diff 仅含文档类文件（`*.md` / `CHANGELOG*` / `.gitignore` / `.opencode/**` / LICENSE / 纯注释）→ 豁免升版，跳到 d。

#### b. 自动识别版本真相源

**全仓 grep 版本声明**（真相源文件往往不在本次暂存清单里——版本没升级时它恰恰是"不变"的）：

```bash
# -e 显式指定 pattern；pathspec 限定候选文件类型；排除 lock/vendor 噪音
git grep -In -iE -e 'version[^=:]*[:=][[:space:]]*["'\'']?v?[0-9]+\.[0-9]+\.[0-9]+' -- \
  '*.go' '*.py' '*.js' '*.ts' '*.rs' '*.java' '*.yaml' '*.yml' '*.json' '*.toml' '*.conf' '*.sh' \
  | grep -vE 'go\.sum|package-lock|vendor/|node_modules/'
```

按优先级过滤命中：

1. **源码版本声明**（真相源）：任意语言的 `version` 常量/变量赋值，如
   `version = "1.1.0"`（Go const）、`Version string = "v1.2.0"`（带 v 前缀）、
   `VERSION = "2.3.1"`、`__version__ = "0.4.2"` 等
2. **配置文件显式 version 字段**：yaml/json/toml 的 `version: X.Y.Z`

排除噪音：`go.sum` / `package-lock.json` / `vendor/` / `node_modules/` / 依赖的版本字符串（如 `sdk v1.38.0`）与**组件/节点级元数据版本**（如节点组件 `Version: "1.0.0"`，与服务版本无关——识别不了就靠用户确认）。
`CHANGELOG` 顶部节仅作**交叉验证**，不作真相源。

- **多文件命中** → 列出全部候选，请用户确认真相源（默认建议全部同步升级）
- **零命中** → 请用户确认；明确"无版本管理"则豁免升版（subject 仍按 d 带占位说明），不猜

**暂存文件清单**（`git diff --cached --name-only`）只用于 a 的豁免判定，不用于圈定 grep 范围。

#### c. 判断暂存中版本是否已升级（强制闸门）

在 `git diff --cached` 中检查版本文件的该行是否有 `-`/`+` 变更：

- **已升级** → 采用暂存后的新版本号，不改文件，进入 d
- **未升级** → 默认 **patch +1**（`v1.2.1 → v1.2.2`），**强制执行，不询问是否升版**：
  1. `sed -i` 替换版本声明行为 patch+1（展示替换前后行）+ `git add <版本文件>`——确保暂存区真实携带升级
  2. 如暂存明显含新功能/新接口，可**附带提示**「按 SemVer 新功能通常 minor+1（v1.2.1 → v1.3.0），如需改用请在确认前说明」——是否升 minor 由用户决策，不替用户拍板；用户改选 minor 则重做替换
  3. 用户明确拒绝升版 → 中止整个 commit 流程（等用户手动处理后重跑）
- **闸门复核（生成 message 前最后一步）**：`git diff --cached` 必须能看到版本行已变更，否则视为未升级，回到本分支强制执行——禁止在版本未升级时生成含新版本号的 message
- 升级后同步提示：CHANGELOG 是否需要补对应版本节（**只提示，不自动写**）

#### d. 版本号落地到 message

- 正常 commit：subject 末尾追加 `（v<版本>）`
- 本次升版：混合 commit 的 body 首条加 `chore(release): v旧 → v新`
- 版本行自身变更**不算代码变更**（见注意事项），豁免判定以版本行之外的 diff 为准

### Step 4：生成候选 message

#### Step 4.1：判断 commit 结构

一次 commit 能不能用一行说清？

- **能** → 单一改动：只写 subject，不写 body
- **不能**（多文件/多领域）→ 混合 commit：subject 概括目标 + body 列 facets

混合 commit 的 subject 写"改了什么 / 为什么要改"，不罗列具体文件或改动项——那是 body 的事。

#### Step 4.2：subject 格式

```
type(scope): 中文描述（v<版本>）
```

- `type` 必选，scope 可选
- 中文描述不超过 50 字，简洁准确
- **末尾必须带版本号**：`（v1.1.0）`，来源为 Step 3.5（升版用新版本，豁免用当前版本）
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
- **本次升版时，body 首条固定**：`- chore(release): v旧 → v新`（版本迁移是其他 facet 的前置事实）

**facet 判定：按对外可独立理解的改动单元，不按代码分层。**

- facet = 用户/调用方能感知的行为变化（新增一个接口、修一个 bug、删一个索引），**不是**该行为的分层实现（biz/data/service 各层函数、测试、生成代码、配套文档都是同一 facet 的组成部分，不单独列）
- facet 描述 = **对外行为本身**，不附实现元信息——分层归属、测试形态、文档同步、代码分布（"实现横跨 X/Y/Z"、"含单测"、"spec 已同步"）一律不写，这些从 Git diff 与 openspec 记录可查
- 同一接口跨多层落地 = **1 个 feat**，不拆成 api/biz/data/service 多条；层内实现细节不进 commit message（Git diff 可查，message 只说清对外行为）
- 只有**能脱离其他 facet 独立存在**的改动才单列：独立修复的 bug、独立的性能/构建变更、独立的功能
- 反例：新增一个 REST 接口拆出 feat(api)/feat(biz)/feat(data)/feat(service) 四条——假分层真重复，正确写法是 1 条 feat 说清接口行为

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
版本检查：
  版本真相源 src/version.go，暂存中已升级 v1.3.0 → v1.4.0 ✓

候选 commit message:
  feat(auth): 新增登录接口（v1.4.0）

确认？[y/e/r/n] (y=yes, e=edit, r=retry, n=abort):
```

#### 混合 commit 示例（含默认升版路径）

```
本次变更：
  storage/storage.go                            (+12 -3, 修复 Seek 错误处理)
  forward/forward.go, worker/writestoragejob.go (加 ctx 超时)
  storage/helper_test.go, storage_test.go       (requireDB 取代 skipIfShortOrNoDB)
  Makefile, build.sh, .golangci.yml             (构建链升级)
  .claude/skills/rbedge-build-test/SKILL.md     (新增 skill)
  openspec/changes/archive/...                  (归档 2 个 change)
版本检查：
  版本真相源 cmd/rbedge/main.go，暂存中未升级
  默认 patch+1：v2.3.1 → v2.3.2，是否同意自动升级并加入本次 commit？
  （暂存明显含新功能时附提示：按 SemVer 新功能通常 minor+1 → v2.4.0，是否改用？是否升 minor 由用户决策）

候选 commit message:
  refactor(storage): openGauss 迁移治理收尾（v2.4.0）

  - chore(release): v2.3.1 → v2.4.0
  - fix(storage): position 文件 Seek 错误显式处理，避免幽灵推进
  - refactor(forward/worker): storage 读写加 5s/10s ctx 超时兜底
  - build: Makefile 精简 + build.sh 默认 arm64 + 接入 golangci-lint
  - docs: 新增 rbedge-build-test skill + 归档 2 个 change

确认？[y/e/r/n] (y=yes, e=edit, r=retry, n=abort):
```

（上例中 storage 测试改动是 fix(storage) 的配套验证，不单列 test facet——按 facet 判定规则归并）

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
- **多版本声明真相源**：源码 const + 配置字段同时命中时，列清单请用户确认；默认建议全部同步升级（避免"升了源码、配置还是旧版"的漂移）
- **版本行自身变更不算代码变更**：若暂存 diff 仅含版本行 + 文档，按豁免处理，防止"改版本 → 又要求升版"死循环
- **升版必须展示 sed 前后行**并等用户确认后才改文件；用户拒绝升级则整体中止，不绕过
- **豁免 commit 不升版但 message 仍带版本**：subject 用当前版本号，让版本在提交历史里始终可追溯
