---
name: test-env
description: 部署/启动/停止/查看 MySQL、openGauss、TiDB、Redis、Nacos、EMQX 测试环境。资源全部在 assets/，目录自包含。触发：起环境 / 部署测试环境 / 启动 mysql / 启动 nacos / 启动 redis / 启动 opengauss / 启动 tidb / 启动 emqx / 环境状态 / 停环境
---

# test-env

> 目录自包含：Compose、SQL、配置、JAR、安装脚本全部位于本目录的 `assets/`。脚本调用一律走 `SCRIPT_DIR/../assets/...`，**不依赖仓库根 `06-数据库/`、`22-Redis/`、`25-Nacos/`、`26-EMQX/`**。

## 触发方式

用户表达"需要测试环境"意图时由 LLM 隐式加载。典型场景：

| 用户意图 | 动作 |
|----------|------|
| "启动 mysql" / "起个 mysql" | 检测 → 启动 MySQL → 输出连接信息 |
| "启动 nacos" / "部署 nacos" | 先确认 openGauss 已运行 → 启动 Nacos |
| "启动 redis" | 检测 → 启动 Redis |
| "启动 emqx" / "部署 emqx" | 检测 → 启动 EMQX |
| "环境状态" / "看看环境" | 运行 `scripts/status.sh` 查看所有组件 |
| "停环境" / "关环境" | 确认后运行 `scripts/down.sh` |
| "起环境" / 未指定组件 | 启动全部组件（数据库 + Redis + Nacos + EMQX） |

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
bash .opencode/skills/test-env/scripts/db.sh up mysql
bash .opencode/skills/test-env/scripts/db.sh up opengauss
bash .opencode/skills/test-env/scripts/db.sh up tidb
bash .opencode/skills/test-env/scripts/db.sh up          # 全部
```

`db.sh` 已封装：docker compose up -d + 健康检查轮询（MySQL/TiDB 60s，openGauss 180s）+ 初始化。AI 不重复实现健康检查。

### Redis

```
bash .opencode/skills/test-env/scripts/redis.sh
```

脚本内置幂等：已运行则跳过。密码 `Test@1234`（见 `assets/redis/redis.conf`）。

### Nacos

```
bash .opencode/skills/test-env/scripts/nacos.sh
```

脚本内置：停旧容器 → 启动 → 90s 内轮询 `/nacos/v1/console/health/readiness` → 验证 server/state 端点。

**前置检查**：调用 Nacos 安装脚本前，先运行 `bash .opencode/skills/test-env/scripts/precheck-nacos.sh` 确认：
1. openGauss 容器已运行
2. Nacos 方言插件存在（`assets/nacos/plugins/*.jar`）
3. `assets/nacos/custom-application.properties` 存在

任一失败则终止，不执行 Nacos 安装。

### EMQX

```
bash .opencode/skills/test-env/scripts/emqx.sh
```

脚本内置：停旧容器 → 启动（bridge 网络，端口 1883/8883/8083/8084/18083）→ 90s 内轮询 `/api/v5/status`（EMQX 5.x 默认凭据 `admin/public`）。

无前置依赖，与其他组件互不耦合。Docker 镜像为 `emqx/emqx:5.2.0`，端口配置参考 Deployment 仓库 `1.7.1/sh/install_emqx.sh`，区别仅在去掉 `rbnetwork` 自定义网络，改用 `localhost` 直连以适配 test-env 跨组件场景。

## Step 3: 健康确认

所有部署脚本已内置超时等待 + 健康检查轮询。脚本返回成功即组件就绪，AI 不重复检查。

## Step 4: 输出连接信息

组件就绪后加载 `references/connection-info.md`，按其中的模板和表格输出连接信息（含端口、用户、密码、DSN、连接命令）。

> 连接信息是部署流程的**必需产出**，调用方（人或其它 AI）凭此连接组件。

## 状态与停止

### 查看状态

运行 `bash .opencode/skills/test-env/scripts/status.sh`，输出表格：组件 | 容器 | 状态 | 端口。

### 停止环境

执行前向用户确认：「将停止所有测试环境容器并清理数据卷。确认？(y/n)」

确认后运行 `bash .opencode/skills/test-env/scripts/down.sh`。

> 数据库数据卷会删除，下次启动重新初始化。Redis 和 Nacos 无持久化卷，仅停止容器。

## 部署后访问（docker exec）

部署完成后按组件选对应的进入方式。**MySQL / TiDB / Redis / Nacos / EMQX 都是普通 CLI**，直接 `docker exec -it` 即可；**openGauss 是特例**：`gsql` 不在 PATH，必须带 `LD_LIBRARY_PATH`。

### 直连类（一行命令即可）

| 组件 | 命令 | 说明 |
|------|------|------|
| MySQL | `docker exec -it mysql mysql -u test_user -p'Test@1234' test_db` | mysql CLI 在容器内 PATH 中 |
| TiDB | `docker exec -it tidb mysql -h 127.0.0.1 -P 4000 -u test_user -p'Test@1234' test_db` | TiDB 容器自带 mysql 客户端 |
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
