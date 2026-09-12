#!/bin/bash
# mongo.sh — Mongo 4.4 测试环境部署（认证模式，自包含）
# 规则：单容器，固定名 mongo、默认端口 27017；已运行则跳过，已停止则 docker start 复用，不存在则创建。
# init-mongo.js 挂载到 /docker-entrypoint-initdb.d/（仅数据目录为空时执行一次）
# root=admin/Test@12345678；业务=test_user/Test@12345678（rbiot 库）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONTAINER_NAME="mongo"
PORT="${MONGO_PORT:-27017}"
ROOT_USER="admin"
ROOT_PWD="Test@12345678"
INIT_JS="$SCRIPT_DIR/../assets/mongo/init-mongo.js"
IMAGE="mongo:4.4"

if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    echo "✅ Mongo 已在运行（容器 $CONTAINER_NAME，端口 $PORT），跳过"
    exit 0
fi

if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    echo "启动已存在的 Mongo 容器 $CONTAINER_NAME..."
    docker start "$CONTAINER_NAME" >/dev/null
else
    echo "创建 Mongo 容器 $CONTAINER_NAME（端口 $PORT，认证模式）..."
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p ${PORT}:27017 \
        -v "$INIT_JS":/docker-entrypoint-initdb.d/init-mongo.js:ro \
        -e MONGO_INITDB_ROOT_USERNAME="${ROOT_USER}" \
        -e MONGO_INITDB_ROOT_PASSWORD="${ROOT_PWD}" \
        -e MONGO_INITDB_DATABASE=rbiot \
        "$IMAGE" >/dev/null
fi

echo "等待 mongod 就绪（root 建号）..."

wait_root() { # wait_root <容器名> <超时秒>
    for _ in $(seq 1 $(($2 / 3))); do
        if docker exec "$1" mongo -u "$ROOT_USER" -p "$ROOT_PWD" \
            --authenticationDatabase admin --quiet \
            --eval 'quit(db.runCommand({ ping: 1 }).ok ? 0 : 1)' >/dev/null 2>&1; then
            return 0
        fi
        sleep 3
    done
    return 1
}

if ! wait_root "$CONTAINER_NAME" 90; then
    echo "❌ Mongo 90s 内未就绪，请执行 'docker logs $CONTAINER_NAME' 排查" >&2
    exit 1
fi

# 业务用户验证（首次创建时由 init-mongo.js 建号；重试等待 init 完成）
echo "验证业务用户 test_user..."
for _ in $(seq 1 10); do
    if docker exec "$CONTAINER_NAME" mongo -u test_user -p 'Test@12345678' \
        --authenticationDatabase rbiot rbiot --quiet \
        --eval 'quit(db.runCommand({ ping: 1 }).ok ? 0 : 1)' >/dev/null 2>&1; then
        echo "✅ Mongo 就绪"
        echo "   容器:   $CONTAINER_NAME"
        echo "   端口:   localhost:$PORT"
        echo "   root:   admin/Test@12345678（authSource=admin）"
        echo "   业务:   test_user/Test@12345678（authSource=rbiot，读写 rbiot）"
        exit 0
    fi
    sleep 3
done

echo "❌ root 已就绪但 test_user 认证失败：init-mongo.js 未生效，请 docker logs $CONTAINER_NAME 排查" >&2
exit 1
