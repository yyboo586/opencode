#!/bin/bash
# mock.sh — 本地 mock 服务部署（自包含）
# endpoint :9096 gRPC（替代 rbendpoint）/ http :9999（替代 DU + 远端 IoT）/ device-sim（设备模拟）
# 规则：源码 assets/mock/，宿主静态编译到 assets/mock/bin/；容器固定名 mock-<name>，host 网络
# 用法：
#   bash mock.sh up [endpoint|http|device-sim|all] [--force] [-- device-sim 参数...]
#   bash mock.sh down [endpoint|http|device-sim|all]
#   bash mock.sh status

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MOCK_DIR="$SCRIPT_DIR/../assets/mock"
BIN_DIR="$MOCK_DIR/bin"
ALL_TARGETS="endpoint http device-sim"

ACTION="${1:-}"
shift || true
TARGETS=()
FORCE=0
EXTRA=()
while [ $# -gt 0 ]; do
    case "$1" in
        endpoint|http|device-sim) TARGETS+=("$1") ;;
        all) TARGETS+=(endpoint http device-sim) ;;
        --force) FORCE=1 ;;
        --) shift; EXTRA=("$@"); break ;;
        *) echo "未知参数: $1" >&2; exit 1 ;;
    esac
    shift
done

wait_port() {
    local port="$1" timeout="${2:-30}" i
    for i in $(seq 1 "$timeout"); do
        if (echo > "/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
            return 0
        fi
        sleep 1
    done
    return 1
}

port_busy() {
    ss -ltn 2>/dev/null | grep -q ":$1 "
}

build_one() {
    local name="$1"
    if ! command -v go >/dev/null 2>&1; then
        echo "❌ 需要宿主 Go 工具链编译 mock（源码 $MOCK_DIR/$name）" >&2
        exit 1
    fi
    mkdir -p "$BIN_DIR"
    (cd "$MOCK_DIR/$name" && CGO_ENABLED=0 go build -o "$BIN_DIR/mock-$name" .)
}

start_one() {
    local name="$1"
    local cname="mock-$name"
    if docker ps --format '{{.Names}}' | grep -qx "$cname"; then
        if [ "$FORCE" != "1" ]; then
            echo "✅ $cname 已在运行，跳过（源码改动用 --force 重建）"
            return 0
        fi
        docker rm -f "$cname" >/dev/null
    elif docker ps -a --format '{{.Names}}' | grep -qx "$cname"; then
        docker rm -f "$cname" >/dev/null
    fi

    if [ "$name" = "endpoint" ] && port_busy 9096; then
        echo "❌ 端口 9096 已被占用（platform/local compose 的 local-mock-endpoint-1？）" >&2
        exit 1
    fi
    if [ "$name" = "http" ] && port_busy 9999; then
        echo "❌ 端口 9999 已被占用（platform/local compose 的 local-mock-http-1？）" >&2
        exit 1
    fi
    if [ "$name" = "device-sim" ] && ! docker ps --format '{{.Names}}' | grep -qx emqx; then
        echo "⚠️  EMQX 容器未运行（device-sim 将重连重试，可先执行 emqx.sh）" >&2
    fi

    build_one "$name"
    docker run -d --name "$cname" --network host \
        -v "$BIN_DIR/mock-$name:/usr/local/bin/mock:ro" \
        alpine:latest /usr/local/bin/mock "${EXTRA[@]}" >/dev/null
    echo "✅ $cname 已启动"
}

cmd_up() {
    if [ "${#TARGETS[@]}" -eq 0 ]; then
        TARGETS=(endpoint http)
    fi
    local t
    for t in "${TARGETS[@]}"; do
        start_one "$t"
    done
    for t in "${TARGETS[@]}"; do
        case "$t" in
            endpoint)
                if wait_port 9096 30; then echo "   endpoint :9096 就绪"; else
                    echo "❌ endpoint 30s 内未监听 9096" >&2
                    docker logs --tail 20 mock-endpoint >&2
                    exit 1
                fi
                ;;
            http)
                if wait_port 9999 30; then echo "   http :9999 就绪"; else
                    echo "❌ http 30s 内未监听 9999" >&2
                    docker logs --tail 20 mock-http >&2
                    exit 1
                fi
                ;;
        esac
    done
}

cmd_down() {
    if [ "${#TARGETS[@]}" -eq 0 ]; then
        TARGETS=(endpoint http device-sim)
    fi
    local t
    for t in "${TARGETS[@]}"; do
        if docker ps -a --format '{{.Names}}' | grep -qx "mock-$t"; then
            docker rm -f "mock-$t" >/dev/null
            echo "已停止 mock-$t"
        fi
    done
}

cmd_status() {
    echo "=== Mock 容器 ==="
    local t found
    for t in $ALL_TARGETS; do
        found="$(docker ps -a --filter "name=^mock-$t$" --format '{{.Names}}  {{.Status}}' 2>/dev/null || true)"
        if [ -n "$found" ]; then
            echo "  $found"
        else
            echo "  mock-$t  未部署"
        fi
    done
    echo "=== 端口 ==="
    local p
    for p in 9096 9999; do
        if port_busy "$p"; then
            echo "  :$p  listening"
        else
            echo "  :$p  -"
        fi
    done
}

case "$ACTION" in
    up) cmd_up ;;
    down) cmd_down ;;
    status) cmd_status ;;
    *)
        echo "用法: bash mock.sh {up [endpoint|http|device-sim|all] [--force] [-- 参数...] | down [目标...] | status}"
        exit 1
        ;;
esac
