# 测试环境连接信息

## 组件速览

### 数据库

| 数据库 | 端口 | 用户 | 密码 | 默认库 |
|--------|------|------|------|--------|
| mysql | 3306 | test_user | Test@1234 | test_db |
| opengauss | 5432 | test_user | Test@1234 | test_db_oracle (Oracle 兼容) |
| tidb | 4000 | test_user | Test@1234 | test_db |
| mongo | 27017 | test_user（rbiot 库）/ admin（root） | Test@12345678 | rbiot |

> 密码源定义在 `assets/database/docker-compose.yml`（自包含；与仓库 `06-数据库/MySQL/scripts/docker-compose.yml`、`06-数据库/openGauss/scripts/docker-compose.yml`、`06-数据库/TiDB/scripts/docker-compose.unistore.yml` 同步）。
>
> ⚠️ Mongo 密码与其余数据库不同（`Test@12345678`，8 位超长以规避 Mongo 4.4 默认密码策略差异），与各容器凭据的全部差异见各组件表格。

### Mongo 认证模型（两个用户，authSource 不同）

| 用户 | 密码 | authSource | 角色 | 用途 |
|------|------|-----------|------|------|
| test_user | Test@12345678 | `rbiot` | readWrite + dbAdmin @ rbiot | 业务连接（server / ETL / verify 工具） |
| admin | Test@12345678 | `admin` | root | 容器管理（建库/建用户/诊断） |

> 由 `assets/mongo/init-mongo.js`（数据目录为空时首次启动自动执行）+ `MONGO_INITDB_*` 环境变量共同初始化。test_user 建在 rbiot 库，业务连接必须 `authSource=rbiot`。

### openGauss 自动初始化 3 个同 user 库，各用不同兼容模式

openGauss 容器一次部署会按 `DBCOMPATIBILITY` 自动创建 3 个同 user 库，各自对应一种兼容模式，切换时**只改库名**：

| 库 | 兼容模式 | `DBCOMPATIBILITY` | 典型用法 |
|---|---|---|---|
| `test_db_oracle` | `A` (Oracle) | `'A'` | PL/SQL、序列、`DUAL`、`NVL` |
| `test_db_mysql` | `B` (MySQL) + dolphin 插件 | `'B'` | `AUTO_INCREMENT`、`SHOW`、反引号 |
| `test_db_pg` | `PG` (PostgreSQL) | `'PG'` | `SERIAL` / `BIGSERIAL`、`jsonb`、原生 `LIMIT/OFFSET` |

> 三种兼容模式均来自 `CREATE DATABASE ... DBCOMPATIBILITY` 参数，详见 `assets/database/init.opengauss.sql`（行 22-24）。
>
> ⚠️ openGauss `CREATE DATABASE` 不显式指定 `DBCOMPATIBILITY` 时，**默认 `'A'` (Oracle 兼容)**（见 init SQL L20 注释）。显式建库建议始终写明 `DBCOMPATIBILITY`。

> ⚠️ **容器内 gsql 调用约定**：`opengauss:7.0.0-RC3` 镜像的 `gsql` 不在 PATH，且依赖 `LD_LIBRARY_PATH=/usr/local/opengauss/lib`。必须用绝对路径并带 `LD_LIBRARY_PATH`，详见 SKILL.md §部署后访问（docker exec）。

### Redis

| 属性 | 值 |
|------|-----|
| 端口 | 6379 |
| 版本 | 7.4 |
| 密码 | Test@1234 |

### Nacos

| 属性 | 值 |
|------|-----|
| HTTP 端口 | 8848 |
| gRPC 端口 | 9848 |
| 版本 | 2.4.3 |
| 鉴权 | 关闭 |
| 后端存储 | openGauss (`nacos_config` 库) |
| 控制台 | `http://localhost:8848/nacos` |
| 前置条件 | openGauss 容器已运行 + `nacos_config` 库已初始化（12 张表） |

### EMQX

| 属性 | 值 |
|------|-----|
| MQTT 端口 | 1883 |
| MQTT/SSL 端口 | 8883 |
| MQTT/WS 端口 | 8083 |
| MQTT/WSS 端口 | 8084 |
| Dashboard 端口 | 18083 |
| 版本 | 5.2.0 |
| Dashboard 鉴权 | admin / public（EMQX 5.x 默认） |
| MQTT 鉴权 | 匿名可连接（开发模式） |
| 控制台 | `http://localhost:18083` |
| 网络 | bridge，端口直连 `localhost` |

## 数据库连接命令 & Go DSN

| 数据库 | 连接命令（默认连 `test_db` / `test_db_oracle`） | Go DSN（3 openGauss 库全列） |
|--------|--------------|--------|
| mysql | `docker exec -it mysql mysql -u test_user -p'Test@1234' test_db` | `test_user:Test@1234@tcp(localhost:3306)/test_db?charset=utf8mb4&parseTime=True` |
| opengauss (`test_db_oracle`) | `docker exec -it opengauss bash -c "LD_LIBRARY_PATH=/usr/local/opengauss/lib /usr/local/opengauss/bin/gsql -h localhost -U test_user -d test_db_oracle -W 'Test@1234'"` | `postgres://test_user:Test@1234@localhost:5432/test_db_oracle` |
| opengauss (`test_db_mysql`) | 同上，`-d test_db_mysql` | `postgres://test_user:Test@1234@localhost:5432/test_db_mysql` |
| opengauss (`test_db_pg`) | 同上，`-d test_db_pg` | `postgres://test_user:Test@1234@localhost:5432/test_db_pg` |
| tidb | `mysql -h 127.0.0.1 -P 4000 -u test_user -p'Test@1234' test_db`（宿主机客户端；TiDB 容器内无 mysql CLI） | `test_user:Test@1234@tcp(localhost:4000)/test_db?charset=utf8mb4&parseTime=True` |
| mongo | `docker exec -it mongo mongo -u test_user -p 'Test@12345678' --authenticationDatabase rbiot rbiot` | `mongodb://test_user:Test@12345678@localhost:27017/rbiot?authSource=rbiot` |

> **Mongo URI 无 authSource 的默认行为**：mongo-driver 默认 authSource=URI 中的库名（即 `rbiot`），与 test_user 所在库一致，业务侧可省略 authSource；但显式写上更稳（防库名变更踩坑）。admin/root 管理操作必须 `--authenticationDatabase admin`。

> **切换兼容模式**：openGauss 用户/密码/端口不变，只换 DSN 或 `gsql -d` 中的库名即可在 3 种兼容层之间切换。

## 输出模板

### 数据库

```
数据库 <type> 已就绪（端口 <port>）

连接信息:
  主机: localhost
  端口: <port>
  用户: <user>
  密码: <password>
  库:   <db>

容器内连接:
  <cmd>

Go DSN:
  <dsn>
```

### Redis

```
Redis 7.4 已就绪（端口 6379）

连接信息:
  主机: localhost
  端口: 6379
  密码: Test@1234

连接命令:
  redis-cli -h localhost -p 6379 -a Test@1234

Go SDK:
  使用 go-redis，地址为 "localhost:6379"，密码 Test@1234
```

### Nacos

```
Nacos 2.4.3 已就绪（HTTP 8848 / gRPC 9848）

连接信息:
  控制台:    http://localhost:8848/nacos
  服务发现:  localhost:8848
  gRPC:      localhost:9848
  鉴权:     已关闭（开发模式）

后端 openGauss:
  主机: host.docker.internal:5432
  库:   nacos_config

Go SDK:
  使用 nacos-sdk-go，ServerConfig.IpAddr = "localhost", Port = 8848
```

### Mongo

```
Mongo 4.4 已就绪（端口 27017，认证模式）

连接信息:
  主机: localhost
  端口: 27017
  业务用户: test_user / Test@12345678（authSource=rbiot，读写 rbiot 库）
  root用户: admin / Test@12345678（authSource=admin，管理操作）

容器内连接:
  docker exec -it mongo mongo -u test_user -p 'Test@12345678' --authenticationDatabase rbiot rbiot

Go DSN:
  mongodb://test_user:Test@12345678@localhost:27017/rbiot?authSource=rbiot
```

### EMQX

```
EMQX 5.2.0 已就绪（MQTT 1883 / Dashboard 18083）

连接信息:
  MQTT:       localhost:1883（匿名可连接）
  MQTT/SSL:   localhost:8883
  MQTT/WS:    localhost:8083
  MQTT/WSS:   localhost:8084
  Dashboard:  http://localhost:18083（admin / public）

MQTT 连接命令:
  mosquitto_pub -h localhost -p 1883 -t test/topic -m "hello"
  mosquitto_sub -h localhost -p 1883 -t test/#

Go SDK:
  使用 eclipse/paho，broker = "tcp://localhost:1883"
```
