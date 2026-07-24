#!/bin/bash
# precheck-nacos.sh — Nacos 启动前置检查（自包含）
# 资源检查仅限定在 assets/nacos/ 内部

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NACOS_DIR="$SCRIPT_DIR/../assets/nacos"

errors=0

echo "=== Nacos 前置检查 ==="

if docker ps --filter "name=opengauss" --format "{{.Names}}" | grep -q opengauss; then
    echo "  [OK] openGauss 容器已运行"
else
    echo "  [FAIL] openGauss 容器未运行，请先启动 openGauss"
    errors=$((errors + 1))
fi

PLUGIN_DIR="$NACOS_DIR/plugins"
if ls "$PLUGIN_DIR"/*.jar 2>/dev/null | grep -q .; then
    echo "  [OK] Nacos 方言插件存在 ($PLUGIN_DIR)"
else
    echo "  [FAIL] Nacos 方言插件不存在: $PLUGIN_DIR"
    errors=$((errors + 1))
fi

CONFIG_FILE="$NACOS_DIR/custom-application.properties"
if [ -f "$CONFIG_FILE" ]; then
    echo "  [OK] custom-application.properties 存在"
else
    echo "  [FAIL] custom-application.properties 不存在"
    errors=$((errors + 1))
fi

echo ""
if [ $errors -eq 0 ]; then
    echo "所有检查通过"
    exit 0
else
    echo "发现 $errors 项检查失败，请先修复再启动 Nacos"
    exit 1
fi
