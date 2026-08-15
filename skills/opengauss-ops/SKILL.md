---
name: opengauss-ops
description: openGauss 日常操作知识（建库/授权/gsql/元数据查询/排障/踩坑/兼容模式）。触发：openGauss 建库 / 授权 / gsql / 查元数据 / 排障 / 踩坑 / 兼容模式
---

# opengauss-ops：openGauss 日常操作知识

> 本 skill 只装**结论与命令**（可直接执行），深度机制与实验原文在 Practice 仓库 `06-数据库/openGauss/docs/`，按 §来源标注回查。

## 触发方式

**显式触发**（用户直接表达 openGauss 意图）：
- "openGauss 建库 / 授权 / gsql / 查元数据 / 排障 / 踩坑 / 兼容模式"

**被动触发**（任务上下文出现 openGauss 特征，AI 主动加载）：
- DSN 为 `postgres://...:5432` 且目标库是 test_db_pg / test_db_mysql / test_db_oracle
- 出现 openGauss 专属词：gsql / pgx / DBCOMPATIBILITY / dolphin / datcompatibility
- 用户排查"SQL 慢 / 不走索引 / 连不上 / 时区不对"，上下文涉及 openGauss
- 写 DDL 涉及 TIMESTAMP / 兼容模式 / 授权，且目标库是 openGauss

## 默认原则

**所有 openGauss 操作默认在 PG 兼容库（test_db_pg）执行**。仅用户明确指定其他兼容模式（B/A）时才切换库。

## 场景速查

### 容器内 gsql 连接

gsql 不在 PATH，必须绝对路径 + LD_LIBRARY_PATH：

```bash
docker exec -it opengauss bash -c \
  "LD_LIBRARY_PATH=/usr/local/opengauss/lib /usr/local/opengauss/bin/gsql -h localhost -U test_user -d test_db_pg -W 'Test@1234'"
```

- `-h localhost` 强制走 TCP，避免 socket 认证问题
- 默认连 test_db_pg（PG 兼容）；切换兼容模式 = 只换 `-d` 库名（test_db_pg / test_db_mysql / test_db_oracle）

### 初始化配置（建库 / 授权 / Search Path）

```sql
-- 由超级用户 omm 执行
-- 1. 建用户
CREATE USER test_user WITH LOGIN PASSWORD 'Test@1234';

-- 2. 建库（显式指定兼容模式）
CREATE DATABASE test_db_pg OWNER test_user DBCOMPATIBILITY = 'PG';  -- PG 兼容（默认，仓库统一）
CREATE DATABASE test_db_mysql OWNER test_user DBCOMPATIBILITY = 'B'; -- MySQL 兼容（仅明确指定时用）
CREATE DATABASE test_db_oracle OWNER test_user DBCOMPATIBILITY = 'A'; -- Oracle 兼容（仅明确指定时用）

-- 3. 切到目标库
\c test_db_pg

-- 4. 建 schema 并授权
CREATE SCHEMA test_schema;
GRANT CREATE ON SCHEMA test_schema TO test_user;
GRANT USAGE ON SCHEMA test_schema TO test_user;

-- 5. 设置 search_path（写服务端配置，对该用户所有连接生效）
ALTER USER test_user SET search_path TO test_schema, public;
```

> ⚠️ 不显式指定 `DBCOMPATIBILITY` 时**默认 A 模式**（Oracle 兼容）——A 模式 `''` 被当 NULL，`NOT NULL DEFAULT ''` 建表失败。**始终显式写明**。

**授权两组合**（覆盖 90% 场景）：
- 只读用户：`GRANT USAGE ON SCHEMA` + `GRANT SELECT ON TABLE`
- 应用账号：再加 schema 的 `CREATE` + 表的 `INSERT/UPDATE/DELETE`

权限层级：数据库 (CONNECT/CREATE/TEMP) → schema (USAGE/CREATE) → 表 (DML)，逐层放行，缺任何一层都不行。Owner 隐式拥有自己对象全部权限，不用 GRANT。

**Search Path 为什么**：`SET search_path` 是 session 级，只对当前连接生效；连接池/DSN 覆盖后不可控。用 `ALTER USER ... SET search_path` 写服务端配置。

### 元数据速查

```sql
-- 查库兼容模式（最常用）
SELECT datname, datcompatibility FROM pg_database WHERE datname = current_database();
-- ⚠️ 不要用 SHOW dbcompatibility（报 unrecognized parameter）

-- 查字符集与排序规则
SELECT datname, datcollate, datctype FROM pg_database WHERE datname = current_database();
```

| 需求 | 命令 |
|------|------|
| 表结构（列+类型+索引+约束） | `\d <schema>.<table>` |
| 索引 | `\di <schema>.*` 或 `SELECT indexname, indexdef FROM pg_indexes WHERE schemaname='<s>' AND tablename='<t>';` |
| 约束 | `SELECT conname, contype, pg_get_constraintdef(oid) FROM pg_constraint WHERE conrelid='<s>.<t>'::regclass;` |
| 活动连接（排查卡住） | `SELECT datname, pid, usename, state, query FROM pg_stat_activity WHERE datname = current_database();` |
| 锁（排查卡住） | `SELECT relation::regclass, mode, granted, pid FROM pg_locks WHERE relation IS NOT NULL AND database = (SELECT oid FROM pg_database WHERE datname = current_database());` |
| 执行计划 | `EXPLAIN (ANALYZE, VERBOSE, BUFFERS) SELECT ...;` |

### 写 TIMESTAMP 列

显式 `TIMESTAMP WITHOUT TIME ZONE`（PG 模式默认）；需时区语义才用 `WITH TIME ZONE`。

### 写 SQL 占位符

用 `$1`（所有模式可用）；`?` 仅 B+dolphin 可用。

### 执行多条 SQL（gsql）

单条 `-c` 或 heredoc：`gsql ... <<'EOF' ... EOF`

### 建 LIKE 前缀索引

`CREATE INDEX idx_<t>_<c>_ops ON <t> (col varchar_pattern_ops);`

### 建 ILIKE 索引

`CREATE INDEX idx_<t>_<c>_lower ON <t> (lower(col));` 查询写 `WHERE lower(col) LIKE lower('abc%')`

### 连接 openGauss（Go）

executor 封装 `NewFromDriver("pgx", dsn, ...)`，不直接用 pgx 原生驱动；占位符 `$1`

### 建 JSON/JSONB 列

用行存表（列存报 `type not supported in column store`）

### 迁移 LIKE 查询（MySQL→openGauss）

大小写不敏感：`ILIKE`（简单）或 `lower(s) LIKE lower(?)`（可走 lower 索引）；PG 库禁用 utf8mb4_* collation

## 来源标注

> 本 skill 是 Practice 仓库 openGauss 文档的**结论快照**（2026-08-14 提炼）。事实源在仓库，更新时按下列路径回查同步：

| 本 skill 内容 | 事实源 |
|--------------|--------|
| 建库/授权/gsql/元数据/排障 | `06-数据库/openGauss/docs/og-基础操作.md` |
| 写 TIMESTAMP 列 | `og-版本行为矩阵.md §A5` |
| 写 SQL 占位符 | `og-版本行为矩阵.md §A10` |
| 执行多条 SQL（gsql） | `og-版本行为矩阵.md §B1` |
| 建 LIKE 前缀索引 / 建 ILIKE 索引 | `og-通用-LIKE与索引.md` |
| 连接 openGauss（Go） | `og-版本行为矩阵.md §A12` |
| 建 JSON/JSONB 列 | `og-版本行为矩阵.md §E2` |
| 迁移 LIKE 查询（MySQL→openGauss） | `06-数据库/docs/调查-openGauss-PG兼容模式字符集与LIKE大小写.md` |
