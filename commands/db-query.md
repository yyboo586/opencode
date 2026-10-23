---
name: "db-query"
description: 只读查询本地测试数据库（MySQL/openGauss/TiDB/Mongo/TXSQL）；连接信息以 test-env skill 为准，不自动起库
category: Database
tags: [database, query, test-env, read-only]
---

用户调用 `/db-query` 时，按以下流程执行。

## 参数

```
/db-query <engine> <database> <query>
/db-query opengauss test_db_pg "select count(*) from t_log"
/db-query mysql test_db "select id, name from t_user limit 5"
/db-query mongo rbiot 'db.forever.find({}, {device_name:1}).limit(5)'
/db-query txsql test_db "select version()"
```

`engine` 只能是：`mysql` / `opengauss` / `tidb` / `mongo` / `txsql`。

## 前置：连接信息只认 test-env

1. 先加载 `test-env` skill，读取：

   ```text
   ~/.config/opencode/skills/test-env/references/connection-info.md
   ```

2. 连接参数（端口/用户/密码/库名/认证库）以该文件为准；**不要在本命令里复制/硬编码密码**。
3. 检查目标容器是否运行：

   ```bash
   docker ps --filter "name=^<container>$" --format '{{.Names}} {{.Status}}'
   ```

4. 未运行就停止，提示用户：

   ```text
   目标数据库未运行。请先用 test-env skill 启动（db.sh up <engine> / mongo.sh / txsql.sh）。
   ```

   **不要自动 `docker compose up`、`db.sh up` 或初始化数据。**

## 只读约束

- 默认只读；不提供写模式。遇到写操作，停止并建议走迁移脚本/明确变更流程。
- SQL 拒绝关键字（大小写不敏感）：

  ```text
  insert update delete drop alter truncate create grant revoke vacuum reindex
  ```

- 允许：`select` / `show` / `describe` / `desc` / `explain` / `with`（`with` 内不得含上述写关键字）。
- Mongo 只允许：`find` / `aggregate` / `count` / `distinct` / `explain`；拒绝 `insert/update/delete/drop/create/rename/remove`。
- 默认行数上限 50：
  - SQL `select` 没有 `limit` 时追加 `limit 50`；
  - Mongo 没有 `.limit(` 时追加 `.limit(50)`；
  - 聚合/计数不强加 limit，但输出只保留前 50 行。

## 执行模板

密码从 `connection-info.md` 取到 shell 变量（例如 `DB_PASSWORD`），执行时引用变量，**回复里不要打印密码**。

### MySQL

```bash
docker exec mysql mysql -u test_user -p"$DB_PASSWORD" "$DB" -e "$SQL"
```

### openGauss（gsql 不在 PATH）

```bash
docker exec opengauss bash -c \
  "LD_LIBRARY_PATH=/usr/local/opengauss/lib /usr/local/opengauss/bin/gsql \
   -h localhost -U test_user -d $DB -W '$DB_PASSWORD' -c \"$SQL\""
```

### TiDB（容器内无 mysql CLI，用宿主机客户端）

```bash
mysql -h 127.0.0.1 -P 4000 -u test_user -p"$DB_PASSWORD" "$DB" -e "$SQL"
```

### TXSQL（容器内交互客户端会崩，用宿主机客户端）

```bash
mysql -h 127.0.0.1 -P 3307 -uroot -p"$DB_PASSWORD" "$DB" -e "$SQL"
```

### Mongo（authSource=rbiot）

```bash
docker exec mongo mongo -u test_user -p "$DB_PASSWORD" \
  --authenticationDatabase rbiot rbiot --quiet --eval "$JS"
```

## 输出

```text
engine=<...> db=<...> rows=<n> elapsed=<...>ms truncated=yes/no
<表格：列名 + 前 50 行>
```

- 不打印连接串/密码；
- 不贴完整结果集；
- 错误只回首行 + 关键提示，例如：
  - `connection refused` → 提示用 test-env 起库；
  - `relation does not exist` → 让用户确认库名/兼容模式（openGauss 三个库）；
  - 语法错误 → 回显 SQL 附近，不重试原句。

## 注意

- 不要用 `SELECT *` 扫大表；先 `count(*)` 或加条件。
- openGauss 三个库按兼容模式选：`test_db_oracle` / `test_db_mysql` / `test_db_pg`，不要默认 Oracle。
- Mongo 业务用户是 `test_user`，`authSource=rbiot`；root 操作才用 `admin`。
- 不把 `db-query` 做成 DB 启停/初始化入口；这些仍由 `test-env` skill 负责。
- 同一查询失败不要原样重跑；先确认容器、库名、权限、SQL 方言。
