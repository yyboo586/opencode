#!/bin/bash
# down.sh — 停止 test-env 部署的测试容器（自包含）
# 只停本 skill 部署的实例（mongo/redis/nacos/emqx 及 -2/-3 后缀实例），不碰用户已有容器

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "停止数据库（compose: mysql/opengauss/tidb）..."
bash "$SCRIPT_DIR/db.sh" down

echo "停止 Redis（含后缀实例）..."
docker ps -a --format '{{.Names}}' | grep -E '^redis(-[0-9]+)?$' | xargs -r docker rm -f

echo "停止 Nacos（含后缀实例）..."
docker ps -a --format '{{.Names}}' | grep -E '^nacos(-[0-9]+)?$' | xargs -r docker rm -f

echo "停止 EMQX（含后缀实例）..."
docker ps -a --format '{{.Names}}' | grep -E '^emqx(-[0-9]+)?$' | xargs -r docker rm -f

echo "停止 Mongo（含后缀实例）..."
docker ps -a --format '{{.Names}}' | grep -E '^mongo(-[0-9]+)?$' | xargs -r docker rm -f

echo ""
echo "所有 test-env 容器已停止"
