---
name: test-env
description: 部署/启动/停止/查看 MySQL、openGauss、TiDB、Mongo、Redis、Nacos、EMQX、Jaeger 测试环境，以及本地 mock（endpoint/http/device-sim）。资源全部在 assets/，目录自包含。触发：起环境 / 部署测试环境 / 启动 mysql / 启动 nacos / 启动 redis / 启动 opengauss / 启动 tidb / 启动 mongo / 启动 emqx / 启动 jaeger / 链路追踪环境 / 启动 mock / 起 endpoint mock / 起 http mock / device-sim / 设备模拟器 / 环境状态 / 停环境
---

# test-env

> 目录自包含：Compose、SQL、配置、JAR、安装脚本全部位于本目录的 `assets/`。脚本调用一律走 `SCRIPT_DIR/../assets/...`，**不依赖仓库根 `06-数据库/`、`22-Redis/`、`25-Nacos/`、`26-EMQX/`**。
>
> **部署规则**：每个组件只部署一个容器，容器名固定（`mysql` / `opengauss` / `tidb` / `mongo` / `redis` / `nacos` / `emqx`），端口用默认值。同名容器已运行 → 跳过；已停止 → `docker start` 复用；不存在 → 新建。配置/初始化脚本通过主机目录挂载注入。

## 触发方式

用户表达"需要测试环境"意图时由 LLM 隐式加载。典型场景：

| 用户意图 | 动作 |
|----------|------|
| "启动 mysql" / "起个 mysql" | 检测 → 启动 MySQL → 输出连接信息 |
| "启动 nacos" / "部署 nacos" | 先确认 openGauss 已运行 → 启动 Nacos |
| "启动 redis" | 检测 → 启动 Redis（已运行则跳过） |
| "启动 mongo" / "起个 mongo" | 检测 → 启动 Mongo（认证模式，已运行则跳过） |
| "启动 emqx" / "部署 emqx" | 检测 → 启动 EMQX（已运行则跳过） |
| "启动 jaeger" / "部署 jaeger" / "链路追踪环境" | 检测 → 启动 Jaeger（已运行则跳过） |
| "启动 mock" / "起 endpoint mock" / "起 http mock" | 检测 → 启动 endpoint(9096) + http(9999) mock（已运行则跳过） |
| "起设备模拟器" / "device-sim" | 检测 EMQX → 启动 device-sim（可带 `-- -device dev001 -interval 5s` 参数） |
| "环境状态" / "看看环境" | 运行 `scripts/status.sh` 查看所有组件 |
| "停环境" / "关环境" | 确认后运行 `scripts/down.sh`（只停本脚本部署的实例，不碰用户已有容器） |
| "起环境" / 未指定组件 | 启动全部组件（数据库 + Redis + Nacos + EMQX + Jaeger） |

> **组件详情**（端口、用户名、密码、DSN、输出模板）见 `references/connection-info.md`，仅在需要输出连接信息时才加载。

## 核心流程

```
用户请求
  │
  ▼
Step 1: 环境检测 — 检查目标容器是否存在/运行（scripts/status.sh 或直接 docker ps）
  │
  ├── 已运行 → Step 4（直接输出连接信息）
  └── 未运行 → Step 2
  │
  ▼
Step 2: 启动服务 — 调用对应部署脚本
  │
  ▼
Step 3: 健康确认 — 各脚本已内置超时等待，返回成功即就绪
  │
  ▼
Step 4: 输出连接信息 — 按 `references/connection-info.md` 中的模板输出
```

## Step 1: 环境检测

按目标组件选择检测方式。需要全部组件状态时直接运行 `scripts/status.sh`，单组件时用 `docker ps` 过滤。

## Step 2: 启动服务

### 数据库

```
bash .opencode/skills/test-env/scripts/db.sh up opengauss
bash .opencode/skills/test-env/scripts/db.sh up mysql
bash .opencode/skills/test-env/scripts/db.sh up tidb
bash .opencode/skills/test-env/scripts/db.sh up mongo
bash .opencode/skills/test-env/scripts/db.sh up          # 全部
```

`db.sh` 已封装：docker compose up -d + 健康检查轮询（MySQL/TiDB/Mongo 60-90s，openGauss 180s）+ 初始化。AI 不重复实现健康检查。

### Redis

```
bash .opencode/skills/test-env/scripts/redis.sh
```

脚本内置：已运行则跳过；已停止则 `docker start` 复用；不存在则按默认端口创建。密码 `Test@1234`（挂载 `assets/redis/redis.conf`），并校验无密码访问被拒（复用旧容器时同样生效）。

### Nacos

```
bash .opencode/skills/test-env/scripts/nacos.sh
```

脚本内置：已运行则跳过；已停止则 `docker start` 复用；不存在则创建。启动后 90s 内轮询 `/nacos/v1/console/health/readiness` → 验证 server/state 端点。

**前置检查**：调用 Nacos 安装脚本前，先运行 `bash .opencode/skills/test-env/scripts/precheck-nacos.sh` 确认：
1. openGauss 容器已运行
2. Nacos 方言插件存在（`assets/nacos/plugins/*.jar`）
3. `assets/nacos/custom-application.properties` 存在

任一失败则终止，不执行 Nacos 安装。

### Mongo

```
bash .opencode/skills/test-env/scripts/mongo.sh
# 或走 db.sh：bash .opencode/skills/test-env/scripts/db.sh up mongo
```

脚本内置：已运行则跳过；已停止则 `docker start` 复用；不存在则创建（固定容器名 mongo、端口 27017）。init-mongo.js 挂载到 `/docker-entrypoint-initdb.d/`（仅首次初始化执行）。root=admin/Test@12345678，业务=test_user/Test@12345678（rbiot 库）。

### EMQX

```
bash .opencode/skills/test-env/scripts/emqx.sh
```

脚本内置：已运行则跳过；已停止则 `docker start` 复用；不存在则创建（bridge 网络，端口 1883/8883/8083/8084/18083）。启动后 90s 内轮询 `/api/v5/status`（EMQX 5.x 默认凭据 `admin/public`）。

无前置依赖，与其他组件互不耦合。Docker 镜像为 `emqx/emqx:5.2.0`，端口配置参考 Deployment 仓库 `1.7.1/sh/install_emqx.sh`，区别仅在去掉 `rbnetwork` 自定义网络，改用 `localhost` 直连以适配 test-env 跨组件场景。

### Jaeger

```
bash .opencode/skills/test-env/scripts/jaeger.sh
```

脚本内置：已运行则跳过；已停止则 `docker start` 复用；不存在则创建（固定容器名 jaeger，OTLP gRPC 4317 / OTLP HTTP 4318 / UI 16686）。启动后 60s 内轮询 `/api/services`。

无前置依赖，与其他组件互不耦合。Docker 镜像为 `jaegertracing/all-in-one:1.62.0`，内存存储（无持久化卷，重启数据清零）。业务服务把 OTLP/HTTP 上报地址配成 `http://localhost:4318/v1/traces` 即可入库（示例见组内 rbruleserver `[tracing]` 配置）。

### 本地 Mock 服务（endpoint / http / device-sim）

```
bash .opencode/skills/test-env/scripts/mock.sh up                        # endpoint :9096 + http :9999（默认）
bash .opencode/skills/test-env/scripts/mock.sh up device-sim             # 设备模拟器（连 EMQX，需 emqx.sh 已起）
bash .opencode/skills/test-env/scripts/mock.sh up device-sim -- -interval 1s -devices 10
bash .opencode/skills/test-env/scripts/mock.sh up --force                # 源码改动后重建容器
bash .opencode/skills/test-env/scripts/mock.sh down / status
```

- 源码在 `assets/mock/`（说明见其 `README.md`）：endpoint 替代 rbendpoint、http 替代 DU + 远端 IoT、device-sim 模拟设备上报/收指令。
- 部署形态：宿主 Go 静态编译到 `assets/mock/bin/` → alpine 容器（固定名 `mock-endpoint` / `mock-http` / `mock-device-sim`，host 网络），脚本内置端口就绪轮询。
- 与 `platform/local/` compose 的 `local-mock-*` 容器端口互斥（9096/9999），勿同时运行；endpoint mock 的 `pb/` 与 rbEdgeServer proto 生成物需同步。

## Step 3: 健康确认

所有部署脚本已内置超时等待 + 健康检查轮询。脚本返回成功即组件就绪，AI 不重复检查。

## Step 4: 输出连接信息

组件就绪后加载 `references/connection-info.md`，按其中的模板和表格输出连接信息（含端口、用户、密码、DSN、连接命令）。

> 连接信息是部署流程的**必需产出**，调用方（人或其它 AI）凭此连接组件。

## 状态与停止

### 查看状态

运行 `bash .opencode/skills/test-env/scripts/status.sh`，输出表格：组件 | 容器 | 状态 | 端口（含 Mock 容器）。

### 停止环境

执行前向用户确认：「将停止所有测试环境容器并清理数据卷。确认？(y/n)」

确认后运行 `bash .opencode/skills/test-env/scripts/down.sh`。

> 数据库数据卷会删除，下次启动重新初始化。Redis 和 Nacos 无持久化卷，仅停止容器。Mock 容器（mock-endpoint / mock-http / mock-device-sim）一并清理。

## 部署后访问（docker exec）

部署完成后按组件选对应的进入方式。**MySQL / Redis / Nacos / EMQX 都是普通 CLI**，直接 `docker exec -it` 即可；**TiDB 容器无 mysql 客户端**，用宿主机 `mysql` 连 4000 端口；**openGauss 是特例**：`gsql` 不在 PATH，必须带 `LD_LIBRARY_PATH`。给用户生产/目标机命令前先核对环境（如部署机 uname -m、busybox 无 pidof -f、容器名 docker ps 实测），不套本地经验（教训：busybox 无 pidof -f 按本地习惯给命令）。

### 直连类（一行命令即可）

| 组件 | 命令 | 说明 |
|------|------|------|
| MySQL | `docker exec -it mysql mysql -u test_user -p'Test@1234' test_db` | mysql CLI 在容器内 PATH 中 |
| TiDB | `mysql -h 127.0.0.1 -P 4000 -u test_user -p'Test@1234' test_db` | 宿主机 mysql 客户端（`pingcap/tidb:v8.5.0` 容器内无 CLI，实测） |
| Mongo | `docker exec -it mongo mongo -u test_user -p 'Test@12345678' --authenticationDatabase rbiot rbiot` | 认证模式；root 管理操作加 `-u admin -p ... --authenticationDatabase admin` |
| Redis | `docker exec -it redis redis-cli -a Test@1234` | entrypoint 启的就是 redis-server，CLI 同容器可用 |
| Nacos | `curl http://localhost:8848/nacos/actuator/health` | 控制台浏览器访问；容器内无 curl 探活需求 |
| EMQX | 浏览器 `http://localhost:18083`（admin / public） | Dashboard HTTP，无 CLI |

### openGauss 特例（`gsql` 不在 PATH）

镜像 `opengauss:7.0.0-RC3` 启动时未把 `/usr/local/opengauss/bin` 加到 `PATH`，`gsql` 必须用**绝对路径** + 显式 `LD_LIBRARY_PATH`，否则会报 `command not found` 或 `libpq.so.*: cannot open`。

```bash
# ❌ 失败：找不到命令
docker exec -it opengauss gsql -U test_user -d test_db_oracle -W 'Test@1234' -c 'SELECT 1;'

# ❌ 失败：找不到动态库
docker exec -it opengauss /usr/local/opengauss/bin/gsql -U test_user -d test_db_oracle -W 'Test@1234' -c 'SELECT 1;'

# ✅ 正确：绝对路径 + LD_LIBRARY_PATH
docker exec -it opengauss bash -c "LD_LIBRARY_PATH=/usr/local/opengauss/lib /usr/local/opengauss/bin/gsql -h localhost -U test_user -d test_db_oracle -W 'Test@1234' -c 'SELECT 1;'"
```

> 切换 3 种兼容模式 = 换库名；3 个库由 `assets/database/init.opengauss.sql` 按 `DBCOMPATIBILITY` 创建，映射如下（**确切值以 init SQL 为准**）：
>
> | 库名 | `DBCOMPATIBILITY` | 典型场景 |
> |------|------------------|----------|
> | `test_db_oracle` | `'A'` (Oracle) | PL/SQL、序列、`DUAL`、`NVL` |
> | `test_db_mysql` | `'B'` (MySQL) + dolphin 插件 | `AUTO_INCREMENT`、`SHOW`、反引号 |
> | `test_db_pg` | `'PG'` (PostgreSQL) | `SERIAL` / `BIGSERIAL`、`jsonb`、原生 `LIMIT/OFFSET` |
>
> 用户/密码/端口不变，只换 DSN 或 `gsql -d` 中的库名即可在 3 种兼容层之间切换。
>
> ⚠️ openGauss `CREATE DATABASE` 不显式指定 `DBCOMPATIBILITY` 时，**默认 `'A'` (Oracle 兼容)**（见 init SQL L20 注释）。显式建库建议始终写明 `DBCOMPATIBILITY`，避免被默认 Oracle 行为影响。

如需反复执行，可定义 shell 函数（贴到 `~/.bashrc`）：

```bash
# test-env: openGauss 容器内 gsql
ogsql() {
    local db="${1:-test_db_oracle}"
    local sql="${2:-SELECT 1;}"
    docker exec -it opengauss bash -c \
        "LD_LIBRARY_PATH=/usr/local/opengauss/lib /usr/local/opengauss/bin/gsql -h localhost -U test_user -d '$db' -W 'Test@1234' -c \"$sql\""
}
# 用法: ogsql test_db_pg "SELECT current_database();"
```

> 容器内已配 `opengauss` 镜像的 `omm` 超级用户；如果用 `docker exec -u omm ...` 切到 `omm`，命令相同，仅权限更宽（建库/改配置）。

## 敏感信息规则

连接信息（含密码）仅在当前 test-env 输出中使用，不写入调查报告、Q-A 文件或其他持久化文档。
