#!/bin/bash
# emqx.sh — EMQX 5.2.0 测试环境部署（自包含）
# 规则（2026-08-29）：同名容器已存在（无论运行/停止）→ 换名换端口新部署，绝不复用/删除已有容器；不挂载主机目录。
# 端口映射：1883 MQTT / 8883 MQTT-SSL / 8083 MQTT-WS / 8084 MQTT-WSS / 18083 Dashboard（占用自动后移）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib-deploy.sh"

IMAGE="emqx/emqx:5.2.0"
CONTAINER_NAME=$(next_name emqx)

# 5 个端口各自独立探测（默认值被占用则 +1 直到空闲）
# 注意：WS/WSS 同段（8083/8084），WSS 必须从 WS 结果之后探测，避免两端口撞值
MQTT_PORT=$(free_port "${EMQX_MQTT_PORT:-1883}")
SSL_PORT=$(free_port "${EMQX_SSL_PORT:-8883}")
WS_PORT=$(free_port "${EMQX_WS_PORT:-8083}")
WSS_PORT=$(free_port $((WS_PORT + 1)))
DASHBOARD_PORT=$(free_port "${EMQX_DASHBOARD_PORT:-18083}")

echo "部署 EMQX（bridge 网络）→ 容器 $CONTAINER_NAME"
docker run -d \
    --name "$CONTAINER_NAME" \
    -p ${MQTT_PORT}:1883 \
    -p ${WS_PORT}:8083 \
    -p ${SSL_PORT}:8883 \
    -p ${WSS_PORT}:8084 \
    -p ${DASHBOARD_PORT}:18083 \
    "$IMAGE"

echo "等待 EMQX 就绪（轮询 http://localhost:${DASHBOARD_PORT}/api/v5/status）..."
for i in $(seq 1 30); do
    if curl -fs -o /dev/null -u admin:public \
        "http://localhost:${DASHBOARD_PORT}/api/v5/status"; then
        echo "✅ EMQX 就绪"
        echo "   容器:     $CONTAINER_NAME"
        echo "   MQTT:     localhost:${MQTT_PORT}（匿名）"
        echo "   Dashboard: http://localhost:${DASHBOARD_PORT}（admin/public）"
        exit 0
    fi
    sleep 3
done

echo "❌ EMQX 90s 内未就绪，请执行 'docker logs $CONTAINER_NAME' 排查" >&2
exit 1
