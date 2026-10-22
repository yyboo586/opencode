---
name: local-session
description: 读取本机 opencode 会话（opencode.db）：按标题/日期定位，默认输出人话摘要（轮次/步数/工具/结论），按需下钻单轮、单步（请求快照）或某条原文。触发：读取本地会话 / 读 session / 看会话 / session 记录 / 上次会话 / 昨天那个会话 / opencode.db 会话
---

# local-session — 读取本机 opencode 会话

## 核心原则

**默认摘要，全文按需下钻。** 一个 89 步的会话全文约 100 万字节（20 万 tokens 量级），
且 90% 是工具输出噪声。先给轮次摘要，用户点名某一轮/某一步再读细节。

| 情况 | 动作 |
|---|---|
| 用户只说"看看 X 会话" | `list` 定位 → `summary` → 问要看哪一轮 |
| 会话 ≤ 20 条消息且 ≤ 100KB | 可直接 `turn` 逐轮读全 |
| 用户说"某一步/某次调用" | `step <session> <index>` |
| 用户说"原文/完整内容" | `raw <session> <messageID> --full` |
| 用户没给 session id | 先 `list <关键词>` 或 `list --date YYYY-MM-DD` |

## 数据源

- 优先：viewer API `http://127.0.0.1:7788`（已实现 v1/v2 双代、timeline、request 快照）
- 兜底：`~/.local/share/opencode/opencode.db`（只读；仅 `list` / `raw`）
- 环境变量：`VIEWER_URL`、`OPENCODE_DB`

脚本（不要手写 SQL/curl，统一走它）：

```bash
S=~/.config/opencode/skills/local-session/scripts/session.py
```

## 命令

```bash
python3 "$S" list [关键词] [--date 2026-10-21] [--limit 10]
python3 "$S" summary <session-id>
python3 "$S" turn <session-id> <轮次>
python3 "$S" step <session-id> <消息序号> [--system] [--full]
python3 "$S" raw <session-id> <messageID> [--full]
```

- `summary` 的 `#` 是轮次（0 基），`起始消息` 列同时给出 `messageID` 和消息序号
- `turn` 的 `<轮次>` 来自 `summary` 的 `#`
- `step` 的 `<消息序号>` 来自 `summary` 的 `起始消息 (#N)` 或 `turn` 输出里的 `#N`
- `--system` 展开系统提示分段全文；`--full` 关闭工具输出截断
- 轮次超出范围时脚本会报错并给出有效范围

## 读取层级

| 层 | 命令 | 内容 | 典型体积 |
|---|---|---|---|
| L0 | `list` | 标题 / id / 时间 / 消息数 | 1–10 行 |
| L1 | `summary` | 总览 + 每轮：问题/步数/工具/结论/ctx | 1–3KB |
| L2 | `turn` | 该轮用户原话 + AI 文字 + 工具名/首行 | 2–10KB |
| L3 | `step` | 系统提示分段 + 历史清单 + 实际 tokens + 返回 | 3–15KB |
| L4 | `raw` | 单条消息原文（工具输出默认截断 2KB） | 按需 |

## 输出约定

- 直接转述脚本结果，**不要原样 dump JSON**
- 引用数字时保留口径：tokens / 字节 / 次
- 摘要里必须保留 `messageID` 和 `#序号`，否则无法下钻
- 工具输出默认截断；用户没要全文就不要加 `--full`
- 会话可能含真实凭据（密码、内网 IP）。**不要在回复里复述**，用 `***` 代替

## 失败处理

- 脚本报 `viewer 不可用`：
  - 先确认 7788 是否在跑：`curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:7788/api/meta`
  - 启动（本机）：`cd /mnt/d/platform/Practice/session-viewer && ./bin/session-viewer >/tmp/opencode/session-viewer.log 2>&1 &`
  - 或设置 `VIEWER_URL` 指向其它实例
- `list` / `raw` 在 viewer 不可用时自动走 SQLite，无需干预
- 找不到会话：换关键词或 `--date`；仍找不到就列最近 10 条让用户选
- 消息 id 不存在：先 `summary` 确认 id，不要猜

## 禁止

- 不要 `SELECT *` 全表扫 7GB 的库；脚本已按会话过滤
- 不要默认读全文/全轮；先摘要
- 不要把整个会话贴进回复；只贴用户问的那一段
- 不要修改 opencode.db（脚本以只读模式打开）
