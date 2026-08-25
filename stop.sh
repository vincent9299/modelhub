#!/bin/bash
# ============================================
# modelhub 停止脚本
# 用法: bash stop.sh          # 只停网关（静态代理保留, 其他程序可能在用）
#       bash stop.sh --all    # 网关 + 静态代理一起停
# ============================================
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

if [ -f logs/gateway.pid ] && kill -0 "$(cat logs/gateway.pid)" 2>/dev/null; then
    PID=$(cat logs/gateway.pid)
    kill "$PID" 2>/dev/null
    sleep 1
    kill -0 "$PID" 2>/dev/null && kill -9 "$PID" 2>/dev/null
    rm -f logs/gateway.pid
    echo "✅ 网关已停止 (PID $PID)"
else
    # macOS/Linux 兼容: pgrep -f 取 PID 再逐个 kill, 避免 pkill -f 匹配到自身/父进程
    PIDS=$(pgrep -f "litellm --config gateway/" 2>/dev/null || true)
    if [ -n "$PIDS" ]; then
        kill $PIDS 2>/dev/null
        sleep 1
        kill -9 $PIDS 2>/dev/null
        echo "✅ 网关已停止 (按进程名)"
    else
        echo "ℹ️  网关未在运行"
    fi
    rm -f logs/gateway.pid
fi

if [ "${1:-}" = "--all" ]; then
    bash static_proxy/stop.sh
fi
