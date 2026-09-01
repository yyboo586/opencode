#!/bin/bash
# nacos-seed.sh — 部署 Nacos 后播种 rbIotDataserver 业务配置（幂等，内容硬编码自包含）
#
# 用途：本地测试链路走真实 Nacos（remoteConfigDb 分支），部署 Nacos 时一次性播种：
#   - dataId=mongo    → Mongo 连接配置（rbIotDataserver 的 DatabaseConfig）
#   - dataId=forward  → 转发配置（ForwardConfigData）
# 不播种（拍板 2026-08-31）：aggregate、mqtt_forward（本地测试链路用不到，报缺再补）
#
# 幂等策略：先 GET 判断，已存在则跳过（--force 覆盖）
# API：Nacos OpenAPI v1，鉴权关闭（test-env custom-application.properties）
#
# 前置条件：
#   1. Nacos 已由 test-env/scripts/nacos.sh 部署并探活
#
# 用法：
#   ./nacos-seed.sh          # 幂等：存在跳过
#   ./nacos-seed.sh --force  # 覆盖已存在配置
#
# 注意（2026-08-31 拍板）：播种内容不读仓内 yml，直接硬编码于此——
# 本脚本是 mongo/forward 配置内容的唯一事实源；configs/ 下同名文件已删除。

set -euo pipefail

FORCE=0
for arg in "$@"; do
    case "$arg" in
        --force) FORCE=1 ;;
    esac
done

NACOS_HOST="${NACOS_HOST:-127.0.0.1}"
NACOS_PORT="${NACOS_PORT:-8848}"
GROUP="iot_data_server"
BASE_URL="http://${NACOS_HOST}:${NACOS_PORT}/nacos/v1/cs/configs"

# ---------- 探活 ----------
if ! curl -sf "http://${NACOS_HOST}:${NACOS_PORT}/nacos/actuator/health" >/dev/null 2>&1; then
    echo "❌ Nacos (${NACOS_HOST}:${NACOS_PORT}) 不可达，先运行 test-env nacos.sh" >&2
    exit 1
fi
echo "Nacos 探活 OK"

# ---------- 播种内容（硬编码，与仓内 configs 同词表；改配置改这里再 --force） ----------
MONGO_CONTENT='host: 127.0.0.1
port: 27017
user: admin
password: Test%4012345678
databasename: rbiot
maxPoolSize: 100
maxWaitTime: 5
writeConcern: majority
logusername: logUser
loguserpwd: passWord1122#4566'

FORWARD_CONTENT='forwardurl: "/api/local/run_scene"
forwardhost: "127.0.0.1"
forwardhttp: "http://"'

# ---------- 通用播种函数 ----------
seed_config() {
    local label="$1"
    shift
    local content="$1"
    local dataId="${label}"

    # GET 判断是否已存在（-sf 在 404 时退出码 22 且无输出，用 -s 不带 f，取 http_code 判断）
    local exists
    exists=$(curl -s -o /dev/null -w "%{http_code}" \
        "http://${NACOS_HOST}:${NACOS_PORT}/nacos/v1/cs/configs?dataId=${dataId}&group=${GROUP}") || exists="ERR"
    if [[ "$exists" == "200" && "$FORCE" != "1" ]]; then
        echo "⏭️  dataId=${dataId} 已存在，跳过（--force 覆盖）"
        return 0
    fi

    # POST 发布（type=yaml；--data-urlencode 保 UTF-8 与换行；-s 不带 f 取 http_code）
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
        "http://${NACOS_HOST}:${NACOS_PORT}/nacos/v1/cs/configs" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "dataId=${dataId}" \
        --data-urlencode "group=${GROUP}" \
        --data-urlencode "type=yaml" \
        --data-urlencode "content=${content}")

    if [[ "$http_code" == "200" ]]; then
        echo "✅ dataId=${dataId} 已播种（内容硬编码于本脚本）"
        return 0
    fi
    echo "❌ dataId=${dataId} 播种失败 HTTP=${http_code}" >&2
    return 1
}

seed_config "mongo"   "$MONGO_CONTENT"
seed_config "forward" "$FORWARD_CONTENT"

# ---------- 回读验证 ----------
echo
echo "=== 回读验证 ==="
for dataId in mongo forward; do
    content=$(curl -sf "http://${NACOS_HOST}:${NACOS_PORT}/nacos/v1/cs/configs?dataId=${dataId}&group=${GROUP}")
    if [[ -n "$content" ]]; then
        echo "✅ GET dataId=${dataId}: $(echo "$content" | head -1) ..."
    else
        echo "❌ GET dataId=${dataId} 为空" >&2
        exit 1
    fi
done

echo
echo "=== 数据库层确认（openGauss config_info）==="
docker exec opengauss su - omm -c "gsql -d nacos_config -c \"SELECT data_id, group_id FROM config_info ORDER BY data_id;\"" 2>/dev/null || \
    echo "（gsql 查询失败，以 API 回读为准）"

echo
echo "🎉 播种完成。rbIotDataserver 测试/服务可直接走 remoteConfigDb → Nacos → 真实 Mongo"