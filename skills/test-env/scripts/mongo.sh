#!/bin/bash
# mongo.sh — Mongo 4.4 测试环境部署（认证模式，自包含）
# 规则（2026-08-29）：同名容器已存在（无论运行/停止）→ 换名换端口新部署，绝不复用/删除已有容器；不挂载主机目录。
# root=admin/Test@12345678；业务=test_user/Test@12345678（rbiot 库，init 由就绪后 docker cp+exec 完成）
# 端口：默认 27017，被占用自动向后探测

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib-deploy.sh"

IMAGE="mongo:4.4"
CONTAINER_NAME=$(next_name mongo)
PORT=$(free_port "${MONGO_PORT:-27017}")
ROOT_USER="admin"
ROOT_PWD="Test@12345678"
INIT_JS="$SCRIPT_DIR/../assets/mongo/init-mongo.js"

echo "部署 Mongo（认证模式）→ 容器 $CONTAINER_NAME（端口 $PORT）"
if [ "$PORT" != "27017" ]; then
    echo "  （27017 已占用，自动换用 $PORT）"
fi

# MONGO_INITDB_ROOT_USERNAME 注入后 entrypoint 自动 --auth；数据目录为容器内匿名卷，无主机挂载
docker run -d \
    --name "$CONTAINER_NAME" \
    -p ${PORT}:27017 \
    -e MONGO_INITDB_ROOT_USERNAME="${ROOT_USER}" \
    -e MONGO_INITDB_ROOT_PASSWORD="${ROOT_PWD}" \
    -e MONGO_INITDB_DATABASE=rbiot \
    "$IMAGE"

echo "等待 mongod 初始化（root 建号）..."

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

# ---- 业务用户初始化（不挂载主机目录 → docker cp 进容器执行）----
echo "初始化业务用户 test_user（docker cp + 执行 init-mongo.js）..."
docker cp "$INIT_JS" "$CONTAINER_NAME":/tmp/init-mongo.js
docker exec "$CONTAINER_NAME" mongo -u "$ROOT_USER" -p "$ROOT_PWD" \
    --authenticationDatabase admin rbiot --quiet /tmp/init-mongo.js >/dev/null 2>&1

# 双重验证
if docker exec "$CONTAINER_NAME" mongo -u test_user -p 'Test@12345678' \
    --authenticationDatabase rbiot rbiot --quiet \
    --eval 'quit(db.runCommand({ ping: 1 }).ok ? 0 : 1)' >/dev/null 2>&1; then
    echo "✅ Mongo 就绪"
    echo "   容器:   $CONTAINER_NAME"
    echo "   端口:   localhost:$PORT"
    echo "   root:   admin/Test@12345678（authSource=admin）"
    echo "   业务:   test_user/Test@12345678（authSource=rbiot，读写 rbiot）"
else
    echo "❌ root 已就绪但 test_user 认证失败：init-mongo.js 未生效，请 docker logs $CONTAINER_NAME 排查" >&2
    exit 1
fi