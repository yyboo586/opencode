#!/bin/bash
# nacos.sh — Nacos 2.4.3 + openGauss 一键启动（自包含）
# 资源位于 assets/nacos/（配置 + 方言插件 jar）
# 前置条件:
#   1. opengauss 容器在跑, 0.0.0.0:5432 端口已开
#   2. omm 密码已设为 Password@1234 (否则 nacos_config 库初始化失败)
#   3. host.docker.internal 在容器内能解析到宿主机

set -euo pipefail

CONTAINER_NAME="nacos"
OLD_CONTAINER_NAME="nacos-derby-test"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NACOS_DIR="$SCRIPT_DIR/../assets/nacos"
LOG_DIR="${LOG_DIR:-$HOME/nacos-logs}"
PLUGINS_DIR="$NACOS_DIR/plugins"
APP_PROPS="$NACOS_DIR/custom-application.properties"
NACOS_IMAGE="nacos/nacos-server:v2.4.3"

NACOS_OPENGauss_HOST="${NACOS_OPENGauss_HOST:-host.docker.internal}"
NACOS_OPENGauss_PORT="${NACOS_OPENGauss_PORT:-5432}"
NACOS_SERVER_PORT="${NACOS_SERVER_PORT:-8848}"
NACOS_GRPC_PORT="${NACOS_GRPC_PORT:-9848}"

# 前置检查
if ! command -v docker &>/dev/null; then
    echo "❌ 找不到 docker 命令" >&2
    exit 1
fi

if [[ ! -d "$PLUGINS_DIR" ]] || ! ls "$PLUGINS_DIR"/*.jar &>/dev/null; then
    echo "❌ $PLUGINS_DIR 下缺少 openGauss 方言插件 jar" >&2
    exit 1
fi

if [[ ! -f "$APP_PROPS" ]]; then
    echo "❌ $APP_PROPS 不存在" >&2
    exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -q "^opengauss$"; then
    echo "❌ opengauss 容器未运行, 请先启动 openGauss" >&2
    exit 1
fi

# 停掉旧 Nacos 释放 8848
if docker ps -a --format '{{.Names}}' | grep -q "^${OLD_CONTAINER_NAME}$"; then
    echo "🛑 停掉老 Nacos: $OLD_CONTAINER_NAME (Derby 模式, 准备切到 openGauss)"
    docker rm -f "$OLD_CONTAINER_NAME" >/dev/null
fi

if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "🛑 停掉已存在的新 Nacos: $CONTAINER_NAME"
    docker rm -f "$CONTAINER_NAME" >/dev/null
fi

mkdir -p "$LOG_DIR"

echo "🚀 启动 $CONTAINER_NAME ($NACOS_IMAGE)"
echo "   日志目录:    $LOG_DIR"
echo "   openGauss:   $NACOS_OPENGauss_HOST:$NACOS_OPENGauss_PORT/nacos_config"

docker run -d --name "$CONTAINER_NAME" \
    -v /etc/localtime:/etc/localtime \
    -v "$LOG_DIR":/home/nacos/logs \
    -v "$PLUGINS_DIR":/home/nacos/plugins:ro \
    -v "$APP_PROPS":/home/nacos/conf/application.properties:ro \
    -e MODE=standalone \
    -e PREFER_HOST_MODE=ip \
    -e TIME_ZONE=Asia/Shanghai \
    -e JVM_XMX=1g \
    -e JVM_XMS=1g \
    -e JVM_XMN=512m \
    -e NACOS_AUTH_ENABLE=false \
    -p "${NACOS_SERVER_PORT}:8848" \
    -p "${NACOS_GRPC_PORT}:9848" \
    --add-host=host.docker.internal:host-gateway \
    "$NACOS_IMAGE"

echo "⏳ 等待 Nacos 启动..."
NACOS_URL="http://127.0.0.1:${NACOS_SERVER_PORT}"
READY=0
for i in $(seq 1 90); do
    if curl -fsS "$NACOS_URL/nacos/v1/console/health/readiness" 2>/dev/null | grep -q "OK"; then
        echo "✅ Nacos 已就绪 (耗时 ${i}s)"
        READY=1
        break
    fi
    sleep 1
done

if [[ "$READY" -ne 1 ]]; then
    echo "❌ Nacos 未在 90 秒内就绪" >&2
    echo "----- 最后 50 行日志 -----" >&2
    docker logs --tail 50 "$CONTAINER_NAME" >&2
    exit 1
fi

echo "🔍 验证 server/state 端点..."
START=$(date +%s%3N)
HTTP_CODE=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 \
    "$NACOS_URL/nacos/v1/console/server/state" 2>/dev/null || echo "000")
END=$(date +%s%3N)
ELAPSED=$((END - START))

echo "   HTTP $HTTP_CODE  耗时 ${ELAPSED}ms"

if [[ "$HTTP_CODE" == "000" ]]; then
    echo "❌ server/state 仍卡死 (>5s 超时)" >&2
    echo "   老 Derby 模式的现象. 检查 openGauss 后端是否真连上." >&2
    echo "   docker exec -u omm opengauss gsql -d nacos_config -U omm -W Password@1234 -c 'SELECT 1;'" >&2
    echo "   容器内解析: docker exec $CONTAINER_NAME sh -c 'getent hosts host.docker.internal'" >&2
    exit 1
fi

WSL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
[[ -z "$WSL_IP" ]] && WSL_IP="127.0.0.1"

echo ""
echo "=========================================="
echo "  ✅ Nacos 2.4.3 + openGauss 启动完成"
echo "=========================================="
echo ""
echo "访问方式:"
echo "  本机:     http://127.0.0.1:${NACOS_SERVER_PORT}/nacos"
if [[ "$WSL_IP" != "127.0.0.1" ]]; then
    echo "  WSL2:     http://${WSL_IP}:${NACOS_SERVER_PORT}/nacos"
fi
echo ""
echo "后端 (openGauss):"
echo "  容器:       $NACOS_OPENGauss_HOST:$NACOS_OPENGauss_PORT/nacos_config"
echo "  库/表数:   1 库 / 12 表"
echo "  日志:       $LOG_DIR"
echo ""
echo "API 探活:"
echo "  健康检查:   curl -sS http://127.0.0.1:${NACOS_SERVER_PORT}/nacos/actuator/health"
echo "  集群状态:   curl -sS http://127.0.0.1:${NACOS_SERVER_PORT}/nacos/v1/console/server/state"
exit 0
