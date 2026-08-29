#!/bin/bash
# nacos.sh — Nacos 2.4.3 + openGauss 部署（自包含）
# 规则（2026-08-29）：同名容器已存在（无论运行/停止）→ 换名换端口新部署，绝不复用/删除已有容器；不挂载主机目录。
# 配置注入：docker create → docker cp（plugins jar + application.properties）→ docker start
# 前置条件:
#   1. opengauss 容器在跑, 0.0.0.0:5432 端口已开
#   2. omm 密码已设为 Password@1234 (否则 nacos_config 库初始化失败)
#   3. host.docker.internal 在容器内能解析到宿主机

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib-deploy.sh"

CONTAINER_NAME=$(next_name nacos)
NACOS_DIR="$SCRIPT_DIR/../assets/nacos"
PLUGINS_DIR="$NACOS_DIR/plugins"
APP_PROPS="$NACOS_DIR/custom-application.properties"
NACOS_IMAGE="nacos/nacos-server:v2.4.3"

NACOS_OPENGauss_HOST="${NACOS_OPENGauss_HOST:-host.docker.internal}"
NACOS_OPENGauss_PORT="${NACOS_OPENGauss_PORT:-5432}"
NACOS_SERVER_PORT=$(free_port "${NACOS_SERVER_PORT:-8848}")
NACOS_GRPC_PORT=$(free_port "${NACOS_GRPC_PORT:-9848}")

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

echo "部署 Nacos → 容器 $CONTAINER_NAME（HTTP $NACOS_SERVER_PORT / gRPC $NACOS_GRPC_PORT）"
if [ "$NACOS_SERVER_PORT" != "8848" ]; then
    echo "  （8848 已占用，自动换用 $NACOS_SERVER_PORT）"
fi

# create → cp（插件 + 配置）→ start，全程无主机目录挂载
CID=$(docker create --name "$CONTAINER_NAME" \
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
    "$NACOS_IMAGE")

docker cp "$PLUGINS_DIR"/. "$CID":/home/nacos/plugins/
docker cp "$APP_PROPS" "$CID":/home/nacos/conf/application.properties
docker start "$CID" >/dev/null

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
echo "  ✅ Nacos 2.4.3 + openGauss 部署完成"
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
echo ""
echo "API 探活:"
echo "  健康检查:   curl -sS http://127.0.0.1:${NACOS_SERVER_PORT}/nacos/actuator/health"
echo "  集群状态:   curl -sS http://127.0.0.1:${NACOS_SERVER_PORT}/nacos/v1/console/server/state"
exit 0