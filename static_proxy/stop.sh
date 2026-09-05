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
    # macOS/Linux 兼容: pgrep -f 取 PID 再逐个 kill, 避免 pkill -f 匹配到自身/父进程
    PIDS=$(pgrep -f "modelhub/static_proxy/mihomo" 2>/dev/null || true)
    if [ -n "$PIDS" ]; then
        kill $PIDS 2>/dev/null
        sleep 1
        kill -9 $PIDS 2>/dev/null
        echo "✅ 已停止 (按进程名)"
    else
        echo "ℹ️  未在运行"
    fi
    rm -f "$PID_FILE"
fi

MIXED_PORT=$(awk '/^mixed-port:/{print $2}' "$DIR/config.yaml" 2>/dev/null); MIXED_PORT=${MIXED_PORT:-7891}
# 端口探测: bash 内建 /dev/tcp, 零外部依赖（nc 在精简容器里常缺失）
if (exec 3<>"/dev/tcp/127.0.0.1/$MIXED_PORT") 2>/dev/null; then
    echo "⚠️  $MIXED_PORT 端口仍在监听, 手动检查: lsof -i :$MIXED_PORT"
else
    echo "✅ $MIXED_PORT 端口已释放"
fi
