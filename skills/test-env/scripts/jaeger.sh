#!/bin/bash
# jaeger.sh — Jaeger 链路追踪测试环境部署（自包含）
# 规则：单容器，固定名 jaeger、默认端口（OTLP gRPC 4317 / OTLP HTTP 4318 / UI 16686）；
#       已运行则跳过，已停止则 docker start 复用，不存在则创建。
# all-in-one 镜像默认内存存储，无持久化卷（链路数据重启即清，测试用途足够）。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONTAINER_NAME="jaeger"
IMAGE="${JAEGER_IMAGE:-jaegertracing/all-in-one:1.62.0}"
OTLP_GRPC_PORT="${JAEGER_OTLP_GRPC_PORT:-4317}"
OTLP_HTTP_PORT="${JAEGER_OTLP_HTTP_PORT:-4318}"
UI_PORT="${JAEGER_UI_PORT:-16686}"

if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    echo "✅ Jaeger 已在运行（容器 $CONTAINER_NAME，UI http://localhost:$UI_PORT），跳过"
    exit 0
fi

if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
    echo "启动已存在的 Jaeger 容器 $CONTAINER_NAME..."
    docker start "$CONTAINER_NAME" >/dev/null
else
    echo "创建 Jaeger 容器 $CONTAINER_NAME（OTLP $OTLP_GRPC_PORT/$OTLP_HTTP_PORT，UI $UI_PORT）..."
    docker run -d \
        --name "$CONTAINER_NAME" \
        -e COLLECTOR_OTLP_ENABLED=true \
        -p "$OTLP_GRPC_PORT":4317 \
        -p "$OTLP_HTTP_PORT":4318 \
        -p "$UI_PORT":16686 \
        "$IMAGE" >/dev/null
fi

echo "等待 Jaeger 就绪（轮询 UI API）..."
for i in $(seq 1 30); do
    if curl -sf "http://localhost:$UI_PORT/api/services" >/dev/null 2>&1; then
        echo "✅ Jaeger 就绪"
        echo "   容器: $CONTAINER_NAME"
        echo "   OTLP: localhost:$OTLP_GRPC_PORT (gRPC) / localhost:$OTLP_HTTP_PORT (HTTP, 上报路径 /v1/traces)"
        echo "   UI:   http://localhost:$UI_PORT"
        exit 0
    fi
    sleep 2
done

echo "❌ Jaeger 60s 内未就绪，请执行 'docker logs $CONTAINER_NAME' 排查" >&2
exit 1
