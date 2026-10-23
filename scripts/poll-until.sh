#!/usr/bin/env bash
# poll-until — repeat a command until it succeeds or output matches, with one final output.
#
# 用法:
#   poll-until [options] -- <command> [args...]
#
# 选项:
#   --interval SEC    轮询间隔，默认 10
#   --timeout SEC     总超时，默认 600
#   --expect REGEX    输出匹配该 ERE 即成功（不要求 exit 0）
#   --fail-regex RE   输出匹配该 ERE 立即失败（exit 1）
#   --max-output BYTES 最终输出最多保留末尾字节，默认 8192
#   --quiet           不打印 attempts/elapsed 状态行
#   -h, --help        帮助
#
# 退出码:
#   0 成功；1 fail-regex 命中；2 用法错误；124 总超时；126/127 命令不可执行/不存在
#
# 设计约束:
#   - 只做“重复执行 + 条件判断 + 输出收敛”，不启动/停止任何服务。
#   - 需要起 DB/服务时先走 test-env skill；本脚本不实现 compose/健康检查。
#   - 每轮输出写临时文件，最终只回显末尾 max-output 字节，避免 N 轮输出进上下文。

set -uo pipefail

interval=10
timeout=600
expect=""
fail_regex=""
max_output=8192
quiet=0

usage() {
    sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-2}"
}

need_arg() {
    if [ "$#" -lt 2 ]; then
        echo "poll-until: $1 需要参数" >&2
        exit 2
    fi
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --interval) need_arg "$@"; interval=$2; shift 2 ;;
        --timeout) need_arg "$@"; timeout=$2; shift 2 ;;
        --expect) need_arg "$@"; expect=$2; shift 2 ;;
        --fail-regex) need_arg "$@"; fail_regex=$2; shift 2 ;;
        --max-output) need_arg "$@"; max_output=$2; shift 2 ;;
        --quiet) quiet=1; shift ;;
        -h|--help) usage 0 ;;
        --) shift; break ;;
        *) echo "poll-until: 未知参数 $1（命令请放在 -- 之后）" >&2; exit 2 ;;
    esac
done

if [ "$#" -lt 1 ]; then
    echo "poll-until: 缺少命令（用法: poll-until [options] -- <command...>）" >&2
    exit 2
fi
if ! [[ "$interval" =~ ^[0-9]+$ ]] || [ "$interval" -lt 1 ]; then
    echo "poll-until: --interval 必须是 >=1 的整数" >&2
    exit 2
fi
if ! [[ "$timeout" =~ ^[0-9]+$ ]] || [ "$timeout" -lt 1 ]; then
    echo "poll-until: --timeout 必须是 >=1 的整数" >&2
    exit 2
fi
if ! [[ "$max_output" =~ ^[0-9]+$ ]] || [ "$max_output" -lt 1 ]; then
    echo "poll-until: --max-output 必须是 >=1 的整数" >&2
    exit 2
fi

tmp="$(mktemp "${TMPDIR:-/tmp}/poll-until.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

log() {
    [ "$quiet" -eq 1 ] || echo "poll-until: $*" >&2
}

start=$(date +%s)
attempt=0
last_rc=0

while :; do
    attempt=$((attempt + 1))
    now=$(date +%s)
    elapsed=$((now - start))
    remaining=$((timeout - elapsed))
    if [ "$remaining" -le 0 ]; then
        log "timeout after ${elapsed}s attempts=${attempt}"
        [ -s "$tmp" ] && tail -c "$max_output" "$tmp"
        exit 124
    fi

    attempt_timeout=$(( remaining < interval ? remaining : interval ))
    [ "$attempt_timeout" -lt 1 ] && attempt_timeout=1

    : > "$tmp"
    timeout "$attempt_timeout" "$@" >"$tmp" 2>&1
    last_rc=$?

    if [ -n "$fail_regex" ] && grep -Eq -- "$fail_regex" "$tmp"; then
        log "fail-regex matched (attempt=${attempt}, rc=${last_rc})"
        tail -c "$max_output" "$tmp"
        exit 1
    fi

    if [ -n "$expect" ]; then
        if grep -Eq -- "$expect" "$tmp"; then
            log "ok attempts=${attempt} elapsed=$(( $(date +%s) - start ))s"
            tail -c "$max_output" "$tmp"
            exit 0
        fi
    elif [ "$last_rc" -eq 0 ]; then
        log "ok attempts=${attempt} elapsed=$(( $(date +%s) - start ))s"
        tail -c "$max_output" "$tmp"
        exit 0
    fi

    if [ "$last_rc" -eq 126 ] || [ "$last_rc" -eq 127 ]; then
        log "command not executable/found (rc=${last_rc})"
        tail -c "$max_output" "$tmp"
        exit "$last_rc"
    fi

    now=$(date +%s)
    elapsed=$((now - start))
    if [ "$elapsed" -ge "$timeout" ]; then
        log "timeout after ${elapsed}s attempts=${attempt} rc=${last_rc}"
        tail -c "$max_output" "$tmp"
        exit 124
    fi

    sleep_for=$(( interval < (timeout - elapsed) ? interval : (timeout - elapsed) ))
    [ "$sleep_for" -lt 1 ] && sleep_for=1
    sleep "$sleep_for"
done
