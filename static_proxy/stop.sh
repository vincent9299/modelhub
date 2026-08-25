#!/bin/bash
# ============================================
# modelhub 静态代理 - 停止脚本
# 用法: bash static_proxy/stop.sh
# 说明: 杀掉 mihomo, 清理 pid; 不留任何 systemd/系统代理
# ============================================
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$DIR")"
PID_FILE="$ROOT/logs/mihomo.pid"

if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    PID=$(cat "$PID_FILE")
    kill "$PID" 2>/dev/null
    sleep 1
    kill -0 "$PID" 2>/dev/null && kill -9 "$PID" 2>/dev/null
    rm -f "$PID_FILE"
    echo "✅ 已停止 (PID $PID)"
else
    pkill -f "modelhub/static_proxy/mihomo" 2>/dev/null && echo "✅ 已停止 (按进程名)" || echo "ℹ️  未在运行"
    rm -f "$PID_FILE"
fi

MIXED_PORT=$(awk '/^mixed-port:/{print $2}' "$DIR/config.yaml" 2>/dev/null); MIXED_PORT=${MIXED_PORT:-7891}
if nc -z -w 2 127.0.0.1 "$MIXED_PORT" 2>/dev/null; then
    echo "⚠️  $MIXED_PORT 端口仍在监听, 手动检查: ss -tlnp | grep $MIXED_PORT"
else
    echo "✅ $MIXED_PORT 端口已释放"
fi
