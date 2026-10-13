---
name: tdsql-ops
description: TDSQL（TXSQL 内核）操作与 MySQL 系方言坑速查（容器连接/建库授权/元数据查询/方言差异：TEXT DEFAULT/1503/序列/保留字/1235/严格 cast/JSON null/字符序/ANALYZE/存量表升级）。触发：TDSQL / TXSQL / txsql / MySQL 方言 / 方言坑 / 方言差异 / 1503 / 1235 / 严格 cast / 保留字 key
---

# tdsql-ops：TDSQL（MySQL 协议系）操作与方言坑速查

> 本 skill 只装**结论与命令**（可直接执行）；深度机制与实验原文在 Practice 仓库
> `06-数据库/TDSQL/docs/tdsql-方言差异与踩坑集.md`，按 §来源回查。

## 触发方式

**显式触发**：用户说 "TDSQL / TXSQL / txsql / MySQL 方言 / 方言坑 / 1530 / 1235 …"。

**被动触发**（任务上下文出现 MySQL 协议系特征）：
- DSN 为 `...@tcp(...:3307)/...` 或 driver == `mysql` 且目标库是 test_db（TDSQL 容器）
- 写 DDL/SQL 准备在 MySQL 系（TDSQL/MySQL/TiDB）执行，涉及：分区表 / TEXT 默认值 /
  索引 IF NOT EXISTS / SEQUENCE / `key` 列名 / JSON 聚合 / ANALYZE / 排序断言
- 排查"MySQL 下报 1064 / 1503 / 1101 / 1235 / 1093 / 静默变 0"

## 默认原则

1. **协议兼容 ≠ 行为兼容**：TXSQL 100% 兼容 MySQL 语法/协议，但仍要按下方陷阱表逐项自查。
2. **方言断言先实测**：建最小表跑一遍再下结论（与 opengauss-ops 同一原则）。
3. **TDSQL 走 executor `mysql` 分支**：不新增 dialect；银行交付为多 proxy 接入（一组
   无状态网关指向同一主备 set），Go 侧用 `rbproxy(h1,h2,...)` 多入口建连（见下）。
4. **脏数据必须可见地失败**：拒绝"静默 0"式宽松转换（见陷阱 6）。

## 场景速查

### txsql 容器连接（test-env）

```bash
bash .opencode/skills/test-env/scripts/txsql.sh        # 起容器（3307；镜像从工作区 txsql-mysql_8.0.30.img load）
# 交互连接一律用宿主机客户端（容器内 mysql 带 TTY 必崩，见下）：
mysql -h127.0.0.1 -P3307 -uroot -p'Test@1234' test_db
# 只能在容器内时：单次执行 / 降级交互（TERM=emacs 走 dumb 分支绕过崩溃，无行编辑补全）：
docker exec txsql mysql -uroot -p'Test@1234' test_db -e 'show databases;'
docker exec -e TERM=emacs -it txsql mysql -uroot -p'Test@1234' test_db
# Go DSN: root:Test@1234@tcp(localhost:3307)/test_db?charset=utf8mb4&loc=UTC&parseTime=true
```

> ⚠️ **容器内交互客户端必崩（2026-10-09 实证）**：`docker exec -it txsql mysql` 打印 banner 后 SIGSEGV（exit 139），任何 TERM / `--no-auto-rehash` 均复现；gdb 根因 = 镜像内 TXSQL 定制客户端（内嵌 libedit）`terminal_set` 调 `tgetstr`，返回指针被按 int 32 位截断（反汇编 `movslq %eax,%rdx`）→ `terminal_alloc` 解引用野指针。仅交互路径（read_history/rl_initialize）触发；`-e` / `--batch` / 无 TTY / 宿主机客户端全正常。SQL 命令本身与 MySQL 一致，与崩溃无关。

建库/授权（root 已建 `root@%`）：

```sql
CREATE DATABASE IF NOT EXISTS test_db DEFAULT CHARACTER SET utf8mb4;
CREATE USER IF NOT EXISTS 'test_user'@'%' IDENTIFIED BY 'Test@1234';
GRANT ALL PRIVILEGES ON test_db.* TO 'test_user'@'%'; FLUSH PRIVILEGES;
```

元数据：`information_schema.tables/PARTITIONS/STATISTICS`（分区列查 `PARTITIONS`、
索引存在性查 `STATISTICS`）。

### 双后端测试（openGauss + TDSQL）

四仓测试统一注入（Executor/testenv 读取；旧名 `TEST_DATABASE_*` 兼容）：

```bash
TEST_DB_DRIVER=mysql TEST_DB_DSN='test_user:Test@1234@tcp(127.0.0.1:3307)/test_db?charset=utf8mb4&loc=UTC' \
  go test ./... -count=1
```

多包跑共享库必须 `-p 1`（串行），否则互相踩库。

### Go 多 proxy 接入（rbproxy，Executor mysql 分支）

```go
// 银行给 N 组 proxy:port（同一 set），DSN 用 rbproxy 列出全部：
exec, err := executor.NewFromDriver("mysql",
    "user:pwd@rbproxy(proxy1:3306,proxy2:3306,proxy3:3306)/db?charset=utf8mb4&loc=UTC&parseTime=true&timeout=2s",
    50, 10, 30*time.Minute, 5*time.Second)
```

- 语义：**建连层选活**（轮转起点顺序尝试，首个成功）；失败候选黑名单 60s 冷却；
  致命配置错误（1045/1044/1049/1130/1698）立即失败不换候选；每候选建连尝试
  默认 3s 超时（DSN `timeout` 可显式指定）。查询错误不驱动切换——由
  `IsTransientError` + 业务重试兜底。
- ⚠️ 多地址**必须用 `rbproxy(...)` 形态**：`tcp(a,b)` 会被驱动 ensureHavePort 改坏并报错引导。
- ⚠️ 候选必须是 **proxy 入口**，不是 DB 节点（直连备库写必失败；直连模式是未做的独立专题）。
- 单 IP 直连照旧：`tcp(host:port)` 零改动兼容。

### 方言陷阱速查表（写 SQL/DDL 前过一遍）

| # | 现象 | 解法（一句话） |
|---|---|---|
| 1 | TEXT 列 `DEFAULT ''` 报 1101 | 写表达式默认 `DEFAULT ('')`（双方言双兼容） |
| 2 | `CREATE INDEX IF NOT EXISTS` / `ADD COLUMN IF NOT EXISTS` / `DROP INDEX IF EXISTS` 报 1064 | 走 `Executor/schemaexec.ExecStmts`（去 IF EXISTS + 1061/1060/1091 容错） |
| 3 | `CREATE SEQUENCE` / `nextval` 报 1064 | MySQL 侧 `AUTO_INCREMENT` + **普通索引**（勿加 UNIQUE——引入 openGauss 没有的唯一性） |
| 4 | 分区表建表报 1503（PK 须含分区键） | 复合 PK `(id, <分区键>)`；唯一键同步含分区键 |
| 5 | `key` 列名到处 1064 | SQL 写 `` `key` ``（openGauss 经 ConvertQuery 转双引号）；⚠️ Go raw string 不能内嵌反引号，用双引号串/拼接 |
| 6 | `CAST('abc' AS DOUBLE)` 静默 0 | 预检查询（JSON_TYPE/REGEXP 白名单）非数值行显式报错 |
| 7 | JSON null 聚合 min 静默 0 | `NULLIF(JSON_UNQUOTE(JSON_EXTRACT(...)), 'null')` 归一 |
| 8 | 排序顺序与 openGauss 不一致 | 跨方言排序不可全等（ci 字符序 vs locale）；断言用确定序字段 |
| 9 | DELETE 带 LIMIT 子查询报 1235/1093 | 派生表包一层 `IN (SELECT id FROM (SELECT ... LIMIT 1) x)` |
| 10 | `ANALYZE t` 报 1064 | `ANALYZE TABLE t`（测试经 `testenv.AnalyzeTable`） |
| 11 | 旧表存在但 `IF NOT EXISTS` 不升级结构 | DROP 重建（测试）/ 独立 ALTER 升级路径（生产待办）；日维护报"表无分区"即此因 |
| 12 | 多仓测试互相踩库 | `-p 1` 串行 + 测试自清残留；同表 DDL 各仓形态必须逐列对齐 |

### 代码侧入口

- `Executor/schemaexec`：DDL 语句切片方言化幂等执行（各仓 EnsureSchema 统一入口）
- `Executor/testenv`：测试注入（Driver/DSN）+ 双方言探针（IndexExists/PartitionExists/RowPartition/AnalyzeTable）
- `Executor/rbproxy.go`：多入口建连故障转移（rbproxy DSN 解析 + 组合 Connector）

## 来源

- 踩坑全文：`Practice/06-数据库/TDSQL/docs/tdsql-方言差异与踩坑集.md`（2026-10-08 四仓双后端实战）
- 字符序三态矩阵：`Practice/06-数据库/openGauss/docs/og-通用-大小写与字符序.md`
- 实战任务档案：`Practice/.opencode/tracking/design-executor-统一母本与TDSQL兼容.md`
- 多 proxy 接入设计与 JDBC 直连模式调研：`Executor/.opencode/tracking/design-rbproxy-多入口建连.md`（2026-10-09）
