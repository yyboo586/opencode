#!/bin/bash
# status.sh — 测试环境组件状态查询（自包含）
# 数据库状态走 assets/database/docker-compose.yml；其余组件直接 docker ps

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DB_COMPOSE="$SCRIPT_DIR/../assets/database/docker-compose.yml"

echo "=== 数据库（compose: mysql/opengauss/tidb/mongo）==="
docker compose -f "$DB_COMPOSE" ps 2>/dev/null || echo "  无运行中的数据库"

echo ""
echo "=== Redis ==="
docker ps --filter "name=redis" --format "{{.Names}}  {{.Status}}  {{.Ports}}" 2>/dev/null || echo "  无运行中的 Redis"

echo ""
echo "=== Nacos ==="
docker ps --filter "name=nacos" --format "{{.Names}}  {{.Status}}  {{.Ports}}" 2>/dev/null || echo "  无运行中的 Nacos"

echo ""
echo "=== Mongo ==="
docker ps --filter "name=^mongo$" --format "{{.Names}}  {{.Status}}  {{.Ports}}" 2>/dev/null || echo "  无运行中的 Mongo"

echo ""
echo "=== EMQX ==="
docker ps --filter "name=emqx" --format "{{.Names}}  {{.Status}}  {{.Ports}}" 2>/dev/null || echo "  无运行中的 EMQX"
