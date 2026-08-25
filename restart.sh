#!/bin/bash
# ============================================
# modelhub 重启: 停网关(不动静态代理) → 重新加载 .env → 自动发现 → 起网关
# 用法: bash restart.sh          # 改 .env 后重载上游配置就用它
#       bash restart.sh --all    # 连静态代理一起重启(改了 static_proxy 规则才需要)
# ============================================
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

if [ "${1:-}" = "--all" ]; then
    bash stop.sh --all
else
    bash stop.sh
fi
sleep 2

exec bash start.sh