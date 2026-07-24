#!/bin/sh
set -u

MAX_RETRY=2

for i in $(seq 1 $MAX_RETRY); do
    if [ $i -eq 1 ]; then
        echo "[entrypoint] 启动 Redis"
    else
        echo "[entrypoint] 上次启动失败，重新尝试 (第 $i/$MAX_RETRY 次)"
    fi
    redis-server /etc/redis/redis.conf
    EXIT_CODE=$?

    if [ $EXIT_CODE -eq 0 ]; then
        exit 0
    fi

    # 检查最近日志是否包含 AOF 中间损坏特征
    if tail -20 /tmp/logs/redis.log 2>/dev/null | grep -q "Bad file format reading the append"; then
        echo "[entrypoint] 检测到 AOF 中间损坏，尝试修复..."
        yes | redis-check-aof --fix /var/lib/redis/appendonlydir/appendonly.aof.manifest 2>&1
        echo "[entrypoint] fix 完成，重新尝试启动"
        continue
    fi

    echo "[entrypoint] 非 AOF 损坏错误，停止重试"
    break
done

echo "[entrypoint] FATAL: Redis 启动失败，请人工介入"
exit $EXIT_CODE