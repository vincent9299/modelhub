#!/bin/bash
# ============================================
# modelhub 静态代理 - 启动脚本
# 用法: bash static_proxy/start.sh
# 说明: nohup 临时拉起 mihomo（mixed 端口仅本机监听）, 不装 systemd, 不设系统代理
#       幂等: 已在运行直接提示
# ============================================
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$DIR")"
MIHOMO="$DIR/mihomo"
LOG_DIR="$ROOT/logs"
LOG="$LOG_DIR/mihomo.log"
PID_FILE="$LOG_DIR/mihomo.pid"
mkdir -p "$LOG_DIR"

# 0. 二进制检查（不存在则先下载/拷贝）
if [ ! -x "$MIHOMO" ]; then
    echo "❌ 缺少 mihomo 二进制: $MIHOMO"
    echo "   下载: bash $DIR/fetch_mihomo.sh   （或从旧机器拷贝）"
    exit 1
fi

# 1. 配置检查（config.yaml 含真实节点凭据, 不入库; 见 README）
if [ ! -f "$DIR/config.yaml" ]; then
    echo "❌ 缺少真实配置: $DIR/config.yaml"
    echo "   参考 config.example.yaml 填入节点信息（或从旧机器拷贝）"
    exit 1
fi

# 2. 幂等: 已在运行直接提示
if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "✅ 静态代理已在运行 (PID: $(cat "$PID_FILE"))"
    exit 0
fi

# 3. 上游隧道可达性检查（server/port 从 config.yaml 解析; 双层链路依赖它）
TUNNEL_SERVER=$(awk '/name: "Tunnel/{f=1} f&&/server:/{print $2; exit}' "$DIR/config.yaml")
TUNNEL_PORT=$(awk '/name: "Tunnel/{f=1} f&&/port:/{print $2; exit}' "$DIR/config.yaml")
# 端口探测: bash 内建 /dev/tcp, 零外部依赖（nc 在精简容器里常缺失, 曾致误报启动失败）
port_open() { (exec 3<>"/dev/tcp/$1/$2") 2>/dev/null; }

if [ -n "${TUNNEL_SERVER:-}" ] && [ -n "${TUNNEL_PORT:-}" ]; then
    if ! port_open "$TUNNEL_SERVER" "$TUNNEL_PORT"; then
        echo "⚠️  上游隧道不可达: $TUNNEL_SERVER:$TUNNEL_PORT（STATIC 双层链路依赖它）"
        echo "   若本机隧道拓扑不同请检查 config.yaml；仍继续启动..."
    fi
fi

# 4. 复制最新配置快照并启动
cp -f "$DIR/config.yaml" "$DIR/config.runtime.yaml" 2>/dev/null
cd "$DIR"
nohup "$MIHOMO" -d "$DIR" -f config.runtime.yaml >> "$LOG" 2>&1 &
echo $! > "$PID_FILE"
sleep 2

# 5. 验证 mixed 端口
MIXED_PORT=$(awk '/^mixed-port:/{print $2}' "$DIR/config.yaml"); MIXED_PORT=${MIXED_PORT:-7891}
if port_open 127.0.0.1 "$MIXED_PORT"; then
    echo "✅ 静态代理已启动 (PID: $(cat "$PID_FILE"), mixed 端口 $MIXED_PORT, 仅本机)"
    echo "   AI API 域名 → STATIC 双层静态出口; 其余直连 (继承宿主策略, modelhub 不感知)"
    echo "   日志: $LOG"
else
    echo "❌ 启动失败, 查看日志: $LOG"
    tail -10 "$LOG"
    exit 1
fi
