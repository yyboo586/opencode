# ============================================================
# bench-common.sh — 基准测试共享函数
# ============================================================

# COMPOSE_CMD 设置
# 2026-06-26 简化：原 WSL 检测逻辑已无意义——
#   - 6.0.5 时代 WSL 需要 healthcheck 覆盖（gsql 不在 PATH），用 docker-compose.wsl.yml
#   - 主 compose 修复后已含全路径 healthcheck，wsl.yml 变成内容冗余
#   - 切到 7.0.0-rc3 + 删除 wsl.yml 后，Linux / WSL / ARM64 配置一致
detect_compose_cmd() {
    local script_dir="$1"
    COMPOSE_CMD="docker compose"
    echo "[INFO] 使用 opengauss:7.0.0-RC3 镜像"
    export COMPOSE_CMD
}

# 等待健康检查通过
# 用 docker compose ps -q 拿容器 ID, 绕开 container_name 硬编码:
#   docker-compose.yml 设了 container_name 时 (如 opengauss), 自动生成的 scripts-xxx-1 命名不再生效,
#   必须用 compose 自己解析服务名→容器 ID 的映射, 才能兼容两种命名。
wait_healthy() {
    local service=$1
    local max_wait=$2
    local compose_file=${3:-}
    local elapsed=0
    echo "[等待] 检查 $service 健康状态..."
    while [ $elapsed -lt $max_wait ]; do
        local cid
        # compose ps 必须带 -f（cwd 不在 compose 目录时找不到项目），兼容旧调用（无第三参时按原行为）
        if [ -n "$compose_file" ]; then
            cid=$($COMPOSE_CMD -f "$compose_file" ps -q "$service" 2>/dev/null | head -1)
        else
            cid=$($COMPOSE_CMD ps -q "$service" 2>/dev/null | head -1)
        fi
        status=$(docker inspect --format='{{.State.Health.Status}}' "$cid" 2>/dev/null || echo "unknown")
        if [ "$status" = "healthy" ]; then
            echo "[OK] $service 已就绪 (等待 ${elapsed}s)"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo "[等待] $service 状态: $status (${elapsed}s/${max_wait}s)"
    done
    echo "[警告] $service 未在 ${max_wait}s 内就绪"
    return 1
}

# DB服务名映射到测试框架名称
db_to_test_name() {
    local db=$1
    case $db in
        mysql)          echo "MySQL" ;;
        opengauss)      echo "openGauss-row" ;;
        tidb)           echo "TiDB" ;;
        *)              echo "$db" ;;
    esac
}

# 所有数据库列表
ALL_DBS="mysql opengauss tidb"