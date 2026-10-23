#!/usr/bin/env bash
# build-test — build then test a Go repo, with short failure output and explicit DB preflight.
#
# 用法:
#   build-test [options] [repo]
#
# 选项:
#   --repo PATH       仓库路径或 /mnt/d/platform 下的目录名（默认当前目录）
#   --build-only      只构建，不跑测试
#   --no-build        跳过构建，只跑测试
#   --with-db         测试必须依赖 test-env 的 opengauss/txsql；未就绪直接失败（不自动启动）
#   --pkg PKG         只跑指定 Go 包（go test PKG）
#   --run REGEX       只跑匹配的测试（go test -run REGEX）
#   --timeout SEC     每步超时，默认 600
#   -h, --help        帮助
#
# 行为:
#   - 有 Makefile build/test 目标时优先用 make；否则回退 go build ./... / go test ./...。
#   - 默认：构建必跑；Makefile test 目标存在且 DB 未就绪时跳过测试并明确提示。
#   - `--with-db`：要求 opengauss/txsql 已运行；未就绪 exit 3，不自行 compose up。
#   - 失败只输出尾部 30 行，并对 DSN/密码做基本脱敏。
#
# 退出码: 0 成功/跳过；1 构建或测试失败；2 用法错误；3 要求 DB 但未就绪。

set -uo pipefail

repo_arg=""
build_only=0
no_build=0
with_db=0
pkg=""
run_regex=""
timeout=600

usage() {
    sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-2}"
}

need_arg() {
    if [ "$#" -lt 2 ]; then
        echo "build-test: $1 需要参数" >&2
        exit 2
    fi
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --repo) need_arg "$@"; repo_arg=$2; shift 2 ;;
        --build-only) build_only=1; shift ;;
        --no-build) no_build=1; shift ;;
        --with-db) with_db=1; shift ;;
        --pkg) need_arg "$@"; pkg=$2; shift 2 ;;
        --run) need_arg "$@"; run_regex=$2; shift 2 ;;
        --timeout) need_arg "$@"; timeout=$2; shift 2 ;;
        -h|--help) usage 0 ;;
        -*) echo "build-test: 未知参数 $1" >&2; exit 2 ;;
        *) repo_arg=$1; shift ;;
    esac
done

if [ -z "$repo_arg" ]; then
    repo_arg="."
fi
if [ -d "$repo_arg" ]; then
    repo="$(cd "$repo_arg" && pwd)"
elif [ -d "/mnt/d/platform/$repo_arg" ]; then
    repo="/mnt/d/platform/$repo_arg"
else
    echo "build-test: 仓库不存在: $repo_arg" >&2
    exit 2
fi

if ! [[ "$timeout" =~ ^[0-9]+$ ]] || [ "$timeout" -lt 1 ]; then
    echo "build-test: --timeout 必须是 >=1 的整数" >&2
    exit 2
fi
if [ ! -f "$repo/go.mod" ] && [ ! -f "$repo/Makefile" ]; then
    echo "build-test: $repo 下没有 go.mod 或 Makefile" >&2
    exit 2
fi

cd "$repo" || exit 2
log="$(mktemp "${TMPDIR:-/tmp}/build-test.XXXXXX")"
trap 'rm -f "$log"' EXIT

has_target() {
    [ -f Makefile ] && grep -qE "^$1[[:space:]]*:" Makefile
}

redact() {
    sed -E \
        -e 's#(://[^:[:space:]]+:)[^@[:space:]]+@#\1***@#g' \
        -e "s#(-p[ =]*)('[^']*'|\"[^\"]*\"|[^[:space:]]+)#\\1***#g" \
        -e 's/([Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]=)[^[:space:]]+/\1***/g'
}

db_ready() {
    command -v docker >/dev/null 2>&1 || return 1
    local c
    for c in opengauss txsql; do
        docker ps --filter "name=^${c}$" --format '{{.Names}}' 2>/dev/null | grep -qx "$c" || return 1
    done
    return 0
}

run_step() {
    local name=$1
    shift
    local start
    start=$(date +%s)
    echo "[$name] $*" >&2
    : > "$log"
    timeout "$timeout" "$@" >"$log" 2>&1
    local rc=$?
    local elapsed=$(( $(date +%s) - start ))
    if [ "$rc" -eq 0 ]; then
        echo "[OK] $name (${elapsed}s)" >&2
        return 0
    fi
    echo "[FAIL] $name rc=${rc} (${elapsed}s)" >&2
    tail -n 30 "$log" | redact >&2
    return "$rc"
}

build_rc=0
if [ "$no_build" -eq 0 ]; then
    if has_target build; then
        run_step "build" make build
    else
        run_step "build" go build ./...
    fi
    build_rc=$?
    if [ "$build_rc" -ne 0 ]; then
        echo "build-test: BUILD FAILED" >&2
        exit 1
    fi
fi

if [ "$build_only" -eq 1 ]; then
    echo "build-test: BUILD OK (tests skipped by --build-only)" >&2
    exit 0
fi

if [ -n "$pkg" ] || [ -n "$run_regex" ]; then
    args=(go test)
    [ -n "$pkg" ] && args+=("$pkg")
    [ -n "$run_regex" ] && args+=(-run "$run_regex")
    args+=(-count=1)
    if run_step "test" "${args[@]}"; then
        echo "build-test: TEST OK" >&2
        exit 0
    fi
    echo "build-test: TEST FAILED" >&2
    exit 1
fi

if has_target test; then
    if [ "$with_db" -eq 1 ] && ! db_ready; then
        echo "build-test: --with-db 要求 opengauss/txsql 已运行；请先加载 test-env skill 启动，不自动起库。" >&2
        exit 3
    fi
    if [ "$with_db" -eq 0 ] && ! db_ready; then
        echo "build-test: BUILD OK；TEST SKIPPED（opengauss/txsql 未就绪）。" >&2
        echo "build-test: 需要测试时先走 test-env skill 起库，再执行 --with-db。" >&2
        exit 0
    fi
    if run_step "test" make test; then
        echo "build-test: TEST OK" >&2
        exit 0
    fi
    echo "build-test: TEST FAILED" >&2
    exit 1
fi

if run_step "test" go test ./... -count=1; then
    echo "build-test: TEST OK" >&2
    exit 0
fi
echo "build-test: TEST FAILED" >&2
exit 1
