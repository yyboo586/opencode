#!/bin/bash
# EMQX 5.2.0 测试环境一键部署
# 用法：bash 26-EMQX/scripts/install_emqx.sh
# 端口映射：1883 MQTT / 8883 MQTT-SSL / 8083 MQTT-WS / 8084 MQTT-WSS / 18083 Dashboard

set -euo pipefail

CONTAINER_NAME="emqx"
IMAGE="emqx/emqx:5.2.0"
DASHBOARD_PORT=18083
MQTT_PORT=1883

if [ -n "$(docker ps -q --filter "name=^/${CONTAINER_NAME}$")" ]; then
    echo "容器 '$CONTAINER_NAME' 已运行"
    exit 0
fi

docker rm -f "$CONTAINER_NAME" 2>/dev/null || true

echo "启动 EMQX 测试容器（bridge 网络）..."
docker run -d \
    --name "$CONTAINER_NAME" \
    -v /etc/localtime:/etc/localtime \
    -p 1883:1883 \
    -p 8083:8083 \
    -p 8883:8883 \
    -p 8084:8084 \
    -p ${DASHBOARD_PORT}:${DASHBOARD_PORT} \
    "$IMAGE"

echo "等待 EMQX 就绪（轮询 http://localhost:${DASHBOARD_PORT}/api/v5/status）..."
for i in $(seq 1 30); do
    if curl -fs -o /dev/null -u admin:public \
        "http://localhost:${DASHBOARD_PORT}/api/v5/status"; then
        echo "✅ EMQX 就绪 (MQTT localhost:${MQTT_PORT} / Dashboard http://localhost:${DASHBOARD_PORT})"
        exit 0
    fi
    sleep 3
done

echo "❌ EMQX 90s 内未就绪，请执行 'docker logs $CONTAINER_NAME' 排查" >&2
exit 1
