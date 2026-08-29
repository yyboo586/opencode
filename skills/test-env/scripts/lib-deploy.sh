#!/bin/bash
# lib-deploy.sh — test-env 部署脚本共享函数
# 规则（2026-08-29）：同名容器已存在（无论运行/停止）→ 换名换端口新部署，不复用不改不删；
#                    一律不挂载主机目录（配置注入走 docker cp 或环境变量）。

# next_name <base> — 输出可用容器名：base、base-2、base-3…
# 与任何已存在容器（运行/停止）重名即顺延后缀，绝不复用。
next_name() {
    local base=$1
    local n=1
    local candidate=$base
    while docker ps -a --format '{{.Names}}' | grep -qx "$candidate"; do
        n=$((n+1))
        candidate="$base-$n"
    done
    echo "$candidate"
}

# free_port <start> — 从 start 向后找第一个未被监听的 TCP 端口
free_port() {
    local p=$1
    while ss -tln "( sport = :$p )" 2>/dev/null | grep -q ":$p "; do
        p=$((p+1))
    done
    echo "$p"
}

# port_busy <port> — 端口是否已被监听（0=占用）
port_busy() {
    ss -tln "( sport = :$1 )" 2>/dev/null | grep -q ":$1 "
}