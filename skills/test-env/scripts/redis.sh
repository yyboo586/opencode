#!/bin/bash
# redis.sh — Redis 测试环境部署（自包含）
# 规则（2026-08-29）：同名容器已存在（无论运行/停止）→ 换名换端口新部署，绝不复用/删除已有容器；不挂载主机目录。
# 端口：默认 6379，被占用自动向后探测；密码 Test@1234（原 redis.conf 核心项内联）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib-deploy.sh"

CONTAINER_NAME=$(next_name redis)
REDIS_PORT=$(free_port "${REDIS_PORT:-6379}")

echo "部署 Redis → 容器 $CONTAINER_NAME（端口 $REDIS_PORT）"
if [ "$REDIS_PORT" != "6379" ]; then
    echo "  （6379 已占用，自动换用 $REDIS_PORT）"
fi

# redis.conf 核心项内联为命令行参数（原 assets/redis/redis.conf：密码 Test@1234 / 512mb LRU / save 300 1）
# 日志走 stdout（docker logs 可查），不挂载主机目录
docker run -d \
    --name "$CONTAINER_NAME" \
    -p "$REDIS_PORT":6379 \
    redis:7.4 \
    redis-server \
        --requirepass 'Test@1234' \
        --maxmemory 512mb \
        --maxmemory-policy allkeys-lru \
        --save 300 1 \
        --dir /data

echo "等待 Redis 就绪（轮询 ping）..."
for i in $(seq 1 30); do
    if docker exec "$CONTAINER_NAME" redis-cli -a 'Test@1234' ping 2>/dev/null | grep -q PONG; then
        echo "✅ Redis 就绪"
        echo "   容器: $CONTAINER_NAME"
        echo "   端口: localhost:$REDIS_PORT"
        echo "   密码: Test@1234"
        exit 0
    fi
    sleep 2
done

echo "❌ Redis 60s 内未就绪，请执行 'docker logs $CONTAINER_NAME' 排查" >&2
exit 1