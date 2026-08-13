#!/bin/bash
# db-env.sh — 数据库环境管理（自包含封装）
# ============================================================
# 与仓库 06-数据库 各库 scripts/（MySQL/scripts/env.sh、openGauss/scripts/deploy.sh、TiDB/scripts/env.sh）等价，但资源全部位于 assets/database/
# 用法:
#   ./scripts/db.sh up                  # 启动全部三个数据库
#   ./scripts/db.sh up mysql            # 启动指定数据库
#   ./scripts/db.sh down                # 停止全部数据库
# 支持的数据库: mysql, opengauss, tidb
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DB_DIR="$SCRIPT_DIR/../assets/database"
COMPOSE_FILE="$DB_DIR/docker-compose.yml"

source "$DB_DIR/lib/bench-common.sh"
detect_compose_cmd "$DB_DIR"

usage() {
    echo "用法:"
    echo "  $0 up              # 启动全部数据库"
    echo "  $0 up <db>         # 启动指定数据库 (mysql|opengauss|tidb)"
    echo "  $0 down            # 停止全部数据库"
    exit 1
}

start_db() {
    local db=$1
    echo ""
    echo "[启动] $db..."

    case $db in
        mysql)
            $COMPOSE_CMD -f "$COMPOSE_FILE" up -d mysql
            wait_healthy mysql 60
            ;;
        tidb)
            $COMPOSE_CMD -f "$COMPOSE_FILE" up -d tidb
            wait_healthy tidb 60
            # TiDB 初始化（不支持 docker-entrypoint-initdb.d）
            echo "[init] TiDB schema 初始化..."
            if command -v mysql &>/dev/null; then
                mysql -h 127.0.0.1 -P 4000 -u root < "$DB_DIR/init.tidb.sql" 2>&1 || echo "[warn] TiDB init 失败，测试侧 initCLogSchema 会兜底建表"
            else
                echo "[warn] mysql CLI 未安装，跳过 TiDB init（测试侧 initCLogSchema 会兜底建表）"
            fi
            ;;
        opengauss)
            $COMPOSE_CMD -f "$COMPOSE_FILE" up -d opengauss
            wait_healthy opengauss 180
            ;;
        *)
            echo "[错误] 不支持的数据库: $db"
            exit 1
            ;;
    esac
    echo "[OK] $db 已就绪"
}

stop_all() {
    echo "[停止] 停止所有测试容器并清理数据卷..."
    $COMPOSE_CMD -f "$COMPOSE_FILE" down -v --remove-orphans
    echo "[OK] 所有容器和数据卷已清理"
}

if [ $# -lt 1 ]; then
    usage
fi

action=$1

case $action in
    up)
        if [ $# -eq 1 ]; then
            echo "=========================================="
            echo "  启动全部数据库"
            echo "=========================================="
            RUNNING=$($COMPOSE_CMD -f "$COMPOSE_FILE" ps --services --filter "status=running" 2>/dev/null || true)
            if [ -n "$RUNNING" ]; then
                echo "[警告] 发现运行中的容器: $RUNNING"
                echo "[提示] 如需重置环境，先执行 $0 down"
            fi
            for db in $ALL_DBS; do
                start_db "$db"
            done
            echo ""
            echo "=========================================="
            echo "  全部数据库已就绪"
            echo "=========================================="
        else
            db=$2
            echo "=========================================="
            echo "  启动 $db"
            echo "=========================================="
            start_db "$db"
        fi
        ;;
    down)
        stop_all
        ;;
    *)
        usage
        ;;
esac
