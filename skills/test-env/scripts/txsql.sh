#!/bin/bash
# txsql.sh — TDSQL（TXSQL 内核）MySQL 兼容测试环境部署（自包含）
# 规则：单容器，固定名 txsql、默认端口 3307（避开 mysql 3306）；已运行则跳过，已停止则 docker start 复用，不存在则创建。
# 镜像来源：工作区根 txsql-mysql_8.0.30.img（docker save 产物）；本机缺镜像时按 TXSQL_IMG 路径 load。
# 契约：TXSQL 8.0 = TencentDB for MySQL（TDSQL 主备）开源内核，100% 兼容原生 MySQL 协议。
#   entrypoint 必需 -e MYSQL_ROOT_PASSWORD；default_authentication_plugin=mysql_native_password（go-sql-driver 无兼容问题）；
#   首次初始化自动建 root@%（远程全权）；业务库 test_db 与 test_user@% 由本脚本自动兜底创建（幂等），
#   与 rblogserver 数据层测试缺省 DSN（test_user）对齐——fresh 环境零配置可跑 make test 默认矩阵。
#
# 用法：
#   bash txsql.sh          # 部署/复用容器，就绪后输出连接信息
#   TXSQL_IMG=/path/txsql-mysql_8.0.30.img bash txsql.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONTAINER_NAME="txsql"
PORT="${TXSQL_PORT:-3307}"
ROOT_PWD="Test@1234"
IMAGE="txsql-mysql:8.0.30"
IMG_SRC="${TXSQL_IMG:-/mnt/d/platform/txsql-mysql_8.0.30.img}"

# 镜像兜底：本机无该镜像时从工作区 img 包 load（平级 mysql/opengauss 均已拉取，正常只跑一次）
if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -qx "$IMAGE"; then
    if [[ -f "$IMG_SRC" ]]; then
        echo "未找到镜像 $IMAGE，从 $IMG_SRC load（约 1s/100MB，dtk ~3.3GB）..."
        docker load -i "$IMG_SRC"
    else
        echo "❌ 镜像 $IMAGE 不在本地，且 IMG_SRC 文件不存在: $IMG_SRC" >&2
        exit 1
    fi
fi

if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    echo "✅ TXSQL 已在运行（容器 $CONTAINER_NAME，端口 $PORT），跳过"
    exit 0
fi

if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    echo "启动已存在的 TXSQL 容器 $CONTAINER_NAME..."
    docker start "$CONTAINER_NAME" >/dev/null
else
    echo "创建 TXSQL 容器 $CONTAINER_NAME（端口 $PORT，MySQL 8.0 兼容内核）..."
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p ${PORT}:3306 \
        -e MYSQL_ROOT_PASSWORD="${ROOT_PWD}" \
        "$IMAGE" >/dev/null
fi

echo "等待 txsql-mysql 就绪（mysqld ping）..."

for _ in $(seq 1 30); do
    if docker exec "$CONTAINER_NAME" mysqladmin -uroot -p"${ROOT_PWD}" ping 2>/dev/null | grep -q "alive"; then
        # 就绪后兜底建 test_db + test_user@%（幂等）：与 rblogserver data 层测试缺省 DSN（test_user）对齐，
        # fresh 环境 make test 默认矩阵（openGauss|pgx txsql|mysql）零配置可跑
        docker exec "$CONTAINER_NAME" mysql -uroot -p"${ROOT_PWD}" -e \
            "CREATE DATABASE IF NOT EXISTS test_db DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
             CREATE USER IF NOT EXISTS 'test_user'@'%' IDENTIFIED BY '${ROOT_PWD}';
             GRANT ALL PRIVILEGES ON test_db.* TO 'root'@'%';
             GRANT ALL PRIVILEGES ON test_db.* TO 'test_user'@'%';
             ALTER USER 'test_user'@'%' IDENTIFIED WITH mysql_native_password BY '${ROOT_PWD}';
             FLUSH PRIVILEGES;" >/dev/null 2>&1
        echo "✅ TXSQL 就绪（TDSQL 开源内核 8.0.30，MySQL 协议分支）"
        echo "   容器:      $CONTAINER_NAME"
        echo "   端口:      localhost:$PORT"
        echo "   账号:      test_user/${ROOT_PWD}（test_user@%，rblogserver 测试缺省）+ root/${ROOT_PWD}（root@%）"
        echo "   免机基线:  default_authentication_plugin=mysql_native_password"
        echo "   测试 DSN:  test_user:Test@1234@tcp(127.0.0.1:${PORT})/test_db?charset=utf8mb4&loc=UTC&parseTime=true"
        exit 0
    fi
    sleep 3
done

echo "❌ TXSQL 90s 内未就绪，请执行 'docker logs $CONTAINER_NAME' 排查" >&2
exit 1
