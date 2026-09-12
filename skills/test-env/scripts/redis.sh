#!/bin/bash
# redis.sh — Redis 测试环境部署（自包含）
# 规则：单容器，固定名 redis、默认端口 6379；已运行则跳过，已停止则 docker start 复用，不存在则创建。
# 配置挂载：assets/redis/redis.conf + entrypoint.sh（AOF 自愈 wrapper）；密码 Test@1234，脚本校验无密码访问被拒

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REDIS_DIR="$SCRIPT_DIR/../assets/redis"
CONTAINER_NAME="redis"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_PWD='Test@1234'

# 密码契约校验：无密码 PING 必须被拒（NOAUTH），带密码 PING 必须通过
verify_auth() {
    if docker exec "$CONTAINER_NAME" redis-cli ping 2>/dev/null | grep -q PONG; then
        echo "❌ Redis 未设置密码（无密码 PING 成功）：redis.conf 未生效" >&2
        echo "   执行 'docker rm -f $CONTAINER_NAME' 后重跑本脚本可重建" >&2
        exit 1
    fi
    if ! docker exec "$CONTAINER_NAME" redis-cli -a "$REDIS_PWD" ping 2>/dev/null | grep -q PONG; then
        echo "❌ Redis 密码校验失败（期望密码 $REDIS_PWD）" >&2
        exit 1
    fi
}

if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    verify_auth
    echo "✅ Redis 已在运行（容器 $CONTAINER_NAME，端口 $REDIS_PORT），跳过"
    exit 0
fi

if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    echo "启动已存在的 Redis 容器 $CONTAINER_NAME..."
    docker start "$CONTAINER_NAME" >/dev/null
else
    echo "创建 Redis 容器 $CONTAINER_NAME（端口 $REDIS_PORT）..."
    docker run -d \
        --name "$CONTAINER_NAME" \
        -p "$REDIS_PORT":6379 \
        -v "$REDIS_DIR/redis.conf":/etc/redis/redis.conf \
        -v "$REDIS_DIR/entrypoint.sh":/usr/local/bin/entrypoint.sh:ro \
        -v /tmp/logs:/tmp/logs \
        redis:7.4 /usr/local/bin/entrypoint.sh >/dev/null
fi

echo "等待 Redis 就绪（轮询 ping）..."
for i in $(seq 1 30); do
    if docker exec "$CONTAINER_NAME" redis-cli -a "$REDIS_PWD" ping 2>/dev/null | grep -q PONG; then
        verify_auth
        echo "✅ Redis 就绪"
        echo "   容器: $CONTAINER_NAME"
        echo "   端口: localhost:$REDIS_PORT"
        echo "   密码: $REDIS_PWD"
        exit 0
    fi
    sleep 2
done

echo "❌ Redis 60s 内未就绪，请执行 'docker logs $CONTAINER_NAME' 排查" >&2
exit 1
