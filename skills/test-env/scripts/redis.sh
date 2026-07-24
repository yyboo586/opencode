#!/bin/bash
# redis.sh — Redis 测试环境一键部署（自包含）
# 附带 AOF 损坏自愈 wrapper（entrypoint.sh）
# 资源位于 assets/redis/

set -euo pipefail

CONTAINER_NAME="redis"
REDIS_PORT=${REDIS_PORT:-6379}
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REDIS_DIR="$SCRIPT_DIR/../assets/redis"

# 幂等检查
if [ -n "$(docker ps -q --filter "name=^/${CONTAINER_NAME}$")" ]; then
    echo "容器 '$CONTAINER_NAME' 已运行"
    exit 0
fi

# 清理旧容器
docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

echo "启动 Redis 测试容器（带 AOF 自愈 wrapper）..."

docker run -d \
    --name "$CONTAINER_NAME" \
    -p "$REDIS_PORT":6379 \
    -v "$REDIS_DIR/redis.conf":/etc/redis/redis.conf \
    -v "$REDIS_DIR/entrypoint.sh":/usr/local/bin/entrypoint.sh:ro \
    redis:7.4-alpine /usr/local/bin/entrypoint.sh

echo "Redis 测试环境就绪 (localhost:$REDIS_PORT)"
