---
name: tool-first
description: 工具选择与输出预算：检索/搜索、读代码、列目录、编辑、重复命令时，优先原生 grep/read/glob/edit，保留 git/构建/测试/docker/DB 的 shell；触发：搜索/查找/读文件/列目录/改文件/重复执行/工具选择/输出太大。
---

# tool-first — 工具选择与输出预算

> 这份 skill 只回答一件事：**当前这一步该用哪个工具，以及输出要控制到多大**。
> 不替代 `local-session`（读会话）、`tdd`（写测试）等专题 skill；专题 skill 命中时仍按专题规则执行。

## 何时用

出现下列任一情况时加载并自检：

- 准备用 shell 执行 `grep`、`rg`、`find`、`ls`、`cat`、`head`、`tail`、`sed -n`；
- 准备读一个源码/配置文件，或搜索跨多文件的符号/文本；
- 准备 edit，但还没 read 目标片段；
- 同一条命令已经重复执行，或准备再执行第 2 次；
- 单次工具输出可能超过 30KB（大文件、全量 grep、日志、diff、DB 结果集）。

## 决策表

| 任务 | 首选 | 什么时候保留 shell |
|---|---|---|
| 代码/文本搜索 | `grep` 工具 | `-c` 计数、`-l` 文件清单、`-o` 只输出匹配、`\| awk/sort/uniq` 聚合、容器/远程内检索 |
| 读源码/配置 | `read` + `offset/limit` | `tail -f` 流式日志、`sed -i` 写入、需要 awk 处理 |
| 找文件名/列目录 | `glob` | `ls -la` 看权限/大小/时间、`du/df`、`find -exec/-mtime/-size` |
| 编辑文件 | `edit`（先 read） | 批量/生成式改写用 `write`；`sed -i` 只在明确需要时 |
| 重复等待/轮询 | 一次 shell 循环（poll-until） | 需要交互式输入、需要保留每轮独立输出时 |
| 构建/测试/lint | shell | 总是 shell：需要真实退出码、工具链、环境变量 |
| git | shell | 总是 shell：diff/show/status/log/commit |
| docker/DB/服务 | shell | 总是 shell：容器内、事务、权限、服务状态 |
| HTTP 本地 API | shell `curl` | 需要鉴权/cookie/管道；外部文档才用 webfetch |

## 五条规则

### 1. 检索优先用 grep 工具

- 跨文件找符号/字符串：`grep(pattern, path, include)`；需要上下文再用 `read` 读命中行附近。
- `grep -rn "x" . | head -20` 不要直接跑 shell；原生 grep 自带截断，head 只会掩盖真实匹配数。
- 需要计数、文件清单、只匹配片段时，才用 `grep -c/-l/-o`；需要排序/去重/聚合时，才用 `| awk/sort/uniq`。
- 容器内/远端文件系统用 `docker exec`/`ssh`，宿主 grep 访问不到。

### 2. 读代码用 read + offset/limit

- `sed -n '140,170p' file` → `read(file, offset=140, limit=31)`；行号、边界、截断由工具处理。
- `cat file` / `head -50 file` / `tail -30 file` 读源码 → `read`；日志才用 `tail -n`/`grep -m`。
- 不要一次把 1000+ 行文件灌进上下文；先读结构（grep 标题/函数名），再读目标段。
- `read` 返回“还有更多内容”是正常分页，不是失败；继续用 offset 读下一段。

### 3. 枚举用 glob

- 找文件名：`glob("internal/**/*.go")`；不要在 shell 里 `ls`/`find | head` 做纯列举。
- 需要权限、大小、mtime、递归过滤、`-exec` 时，保留 `ls -la`/`find`/`du`。
- `find ... -name "*.go" | head` 通常可以直接换 glob；`find ... -mtime -1` 不行。

### 4. edit 前先 read

- oldString 必须来自当前文件内容；不要凭记忆/上一次会话的内容拼。
- `oldString == newString` 直接 no-op，不要调用 edit。
- 多匹配时加 3–5 行上下文；全量替换/生成文件用 `write`，不要用一堆 edit 拼。
- 失败后不要原样重试；先 read 确认空白、引号、缩进、CRLF 是否变化。

### 5. 输出预算

- 单次工具输出目标 ≤30KB；超过时改为摘要、分页、收窄路径或加 `-m`/`--include`。
- 搜索先限定目录/文件类型；不要从仓库根全量 grep。
- 日志只取 `tail -n 50` 或 `grep -m 20`；不要 `cat` 整个日志。
- diff 先 `--stat`，再按文件分段看；不要让 1000 行 diff 一次进上下文。
- DB 查询默认 `LIMIT 50`；只选需要的列；不要把整表结果打印出来。

## 正例 / 反例

| 反例（shell） | 正例（原生工具） | 说明 |
|---|---|---|
| `grep -rn "Dialect interface" . \| head -60` | `grep(pattern="Dialect interface", path=".")` | 原生 grep 自己截断，且带行号 |
| `sed -n '140,170p' storage.go` | `read(path="storage.go", offset=140, limit=31)` | 行号/边界由 read 处理 |
| `cat internal/data/trace.go` | `read(path="internal/data/trace.go")` | 避免整文件灌入；需要时再 offset |
| `ls /mnt/d/platform/Deployment/` | `glob(pattern="*", path="/mnt/d/platform/Deployment")` | 纯列目录 |
| `find . -name "*.go" \| head -100` | `glob(pattern="**/*.go", path=".")` | 纯文件名枚举 |
| `grep -c "pattern" file` | 保留 shell | 计数是 native grep 不直接给的 |
| `grep -rn "x" . \| awk -F: '{print $1}' \| sort -u` | 保留 shell | 聚合/去重必须 shell |
| `docker exec db gsql -c "select ..."` | 保留 shell | 容器内 DB，宿主工具不可达 |

## 重复命令

- 同一命令第 2 次执行前先问：是不是在等状态？如果是，改成一次循环：
  - `poll-until --interval 10 --timeout 900 -- <command>`；
  - 只输出最终状态 + 最后 N 行，不打印每一轮。
- 构建/测试反复重跑：用固定模板（build → vet → test），失败只回尾部 30 行 + exit code。
- DB 轮询：查询加 `LIMIT`，循环里只取一个标量/一行；不要每轮打印全表。

## 与其它 skill 的边界

- `local-session`：读会话记录时用它；本 skill 不教怎么读 session。
- `tdd`：写/改/审测试时用它；本 skill 只决定测试命令怎么跑、输出怎么收。
- `web-tools-guide`：联网搜索/抓取时用它；本 skill 不替代 web 工具的错误处理。
- 用户显式要求用 shell/管道时，按用户要求执行；本 skill 是一般约定，不是硬拦截。
- 项目级 `AGENTS.md` 有更具体命令/路径约定时，以项目级为准。

## 复跑指标

工具选择改动的效果用数据验证，不看感觉：

| 指标 | 基线（2026-10） | 目标（两周后） |
|---|---:|---:|
| v2 shell 占比 | 50.5% | ≤45% |
| v2 检索占 shell | 38.8% | ≤30% |
| edit oldString 失败 | 449 | ≤300 |
| 同会话重复多余 | 1,427 | ≤1,000 |
| peak context p90 | 360K | ≤330K |

复跑：工作区 `.opencode/memory/tool-call-audit.py`（如存在）：

```bash
python3 .opencode/memory/tool-call-audit.py \
  --out /tmp/opencode/audit_after.json \
  --summary /tmp/opencode/audit_after.md
```

只看 `global.signals` 和 `sessions[].gen == "v2"` 的 `cats.search`、`replace`、`edit_fail_kind`、`duplicate_extra`。

## 一句话

**能原生工具做的，不要用 shell 绕；必须 shell 的（git/构建/测试/docker/DB/服务/管道聚合/容器远程），不要硬换。**
