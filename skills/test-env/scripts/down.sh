#!/bin/bash
# down.sh — 停止所有测试环境容器并清理数据卷（自包含）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "停止数据库..."
bash "$SCRIPT_DIR/db.sh" down

echo "停止 Redis..."
docker rm -f redis 2>/dev/null || true

echo "停止 Nacos..."
docker rm -f nacos 2>/dev/null || true

echo "停止 EMQX..."
docker rm -f emqx 2>/dev/null || true

echo ""
echo "所有测试环境容器已停止"
