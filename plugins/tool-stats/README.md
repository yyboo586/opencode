# tool-stats — 工具调用统计（插件 + 报表）

记录 OpenCode 的每次工具调用，输出 JSONL；`report.sh` 用 jq 聚合出次数、失败数、平均耗时、命令词排行、慢调用。

## 文件

| 文件 | 说明 |
|---|---|
| `../tool-stats.ts` | 插件本体（全局自动加载，双兼容 v1/v2） |
| `report.sh` | 报表脚本（jq 聚合，无其他依赖） |
| `stats-history.py` | 历史复算：解析 opencode.db（插件上线前的记录） |
| 数据 | `~/.local/share/opencode/tool-stats/YYYY-MM.jsonl`（按月分文件，插件自动创建） |

## 背景（插件上线前的历史样例）

`stats-history.py` 复算 2026-05-28 ~ 09-28（1002 会话 / 99,480 次调用）：

```
shell+bash 47% | read 23% | edit 14% | grep 5% | todowrite 4% | write 3% | glob 2% | …
bash 命令词 top：grep、head、echo、git、docker、ls、go、cd、tail、sed、python3、cat、find、curl、awk、rg、gsql、golangci-lint
```

## 使用

```bash
plugins/tool-stats/report.sh              # 当月
plugins/tool-stats/report.sh 2026-09      # 指定月
plugins/tool-stats/report.sh 2026-09-28   # 指定日
```

## JSONL 字段

每行一条工具调用（在调用结束时写入）：

| 字段 | 含义 |
|---|---|
| `ts` | 结束时间（epoch 毫秒） |
| `tool` | 工具名：shell / read / edit / grep / …（v2 为 `shell`，v1 为 `bash`） |
| `status` | `completed` / `error`（v2；v1 无此字段） |
| `ms` | 执行耗时（毫秒；before/after 配对成功时才有） |
| `sid` | 会话 ID |
| `agent` | 执行该调用的 agent |
| `w` | bash/shell 的命令首词（如 `git`、`docker`；只取词，不落命令全文） |

## 说明

- **隐私**：只记录命令首词，不记录命令全文与工具参数内容。
- **v1 回滚可用**：插件双兼容（v2 `setup(ctx)` + v1 `server()`），回滚 v1 后继续统计（无 status 字段）。
- **停用/清理**：删除 `plugins/tool-stats.ts` 即停止统计（数据保留）；数据按月删除或归档即可。
- **多实例**：工具 hook 按 location 实例注册，同一次调用只记一次；若发现同会话重复记录请反馈。
