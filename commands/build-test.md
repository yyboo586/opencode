---
name: "build-test"
description: 对指定仓库执行 build + test，失败只回尾部；测试需要 DB 时只检查 test-env 状态，不自动起库
category: Testing
tags: [build, test, go, test-env]
---

用户调用 `/build-test` 时，按以下流程执行。

## 参数

```
/build-test                         # 当前目录
/build-test rbiotserver             # /mnt/d/platform/rbiotserver
/build-test rbiotserver --build-only
/build-test rbiotserver --pkg ./storage/repository --run TestFind
/build-test rblogserver --with-db   # 要求 openGauss/TXSQL 已由 test-env 起好
```

## 执行

1. 只调用固定脚本，不要手工重写 `go build`/`go test` 命令：

   ```bash
   ~/.config/opencode/scripts/build-test.sh <参数...>
   ```

2. 脚本行为：
   - 有 `Makefile` 的 `build` / `test` 目标时优先 `make build` / `make test`；
   - 没有时回退 `go build ./...` / `go test ./... -count=1`；
   - 失败只输出尾部 30 行，并对 DSN/密码做基本脱敏；
   - `--with-db` 只检查 `opengauss`/`txsql` 是否运行；未就绪返回 exit 3，**不自动启动**。

3. 根据退出码处理：

   | exit | 含义 | 动作 |
   |---:|---|---|
   | 0 | 构建成功；测试通过或按规则跳过 | 汇总 build/test 状态 |
   | 1 | 构建或测试失败 | 贴尾部错误 + 失败包/用例；不要原样重试 |
   | 2 | 参数/仓库错误 | 指出正确用法 |
   | 3 | `--with-db` 但 DB 未就绪 | 停止；提示先加载 `test-env` skill 启动数据库 |

## DB 依赖

- 本命令**不负责**起库、初始化、跑 healthcheck；这些属于 `test-env` skill。
- 如果测试需要 DB：
  1. 先让用户用 `test-env` 起 `opengauss` / `txsql`（或 `mysql` / `mongo`）；
  2. 再执行 `/build-test <repo> --with-db`；
  3. 不要把 `docker compose up`、`db.sh up`、密码写进本命令。
- 连接参数以 `~/.config/opencode/skills/test-env/references/connection-info.md` 为准；本命令不复制凭据。

## 输出

```text
repo=<path>  build=OK  test=OK|SKIPPED|FAILED  db=ready|missing
- 失败时：失败包/用例 + 尾部 30 行 + exit code
- 跳过时：说明缺哪个容器（opengauss/txsql），下一步用 test-env
- 不要贴完整编译日志；不要把测试 DSN/密码打进回复
```

## 注意

- 不自动 `git commit` / `git stash`；不修改测试代码来“让测试过”。
- 测试红是任务结果，不是工具失败；先分类（编译/环境/断言），再决定下一步。
- 同一失败不要原样重跑；先修因，或缩小到 `--pkg`/`--run`。
