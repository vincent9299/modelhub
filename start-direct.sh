#!/bin/bash
# ============================================
# modelhub 直连启动 (外网服务器专用, 无代理)
# 适用: 43.160.250.196 (腾讯云海外) —— 所有上游直连可达
# 与 start.sh 的区别:
#   1. 不启动 static_proxy (mihomo) —— 外网无需代理
#   2. 清空 http_proxy/https_proxy/no_proxy —— 防注入死代理
#   3. 其余流程一致: 加载 .env → 生成模型清单 → 启动 litellm
# 停止: bash stop.sh --all
# ============================================
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"
mkdir -p logs

# 0. 关键: 清空代理(外网直连) —— 必须先于任何网络请求
unset all_proxy ALL_PROXY http_proxy HTTP_PROXY https_proxy HTTPS_PROXY no_proxy NO_PROXY
unset DEBUG DETAILED_DEBUG

# 1. 加载 .env
if [ -f .env ]; then
    set -a; . ./.env; set +a
else
    echo "⚠️  未找到 .env, 按默认值继续"
fi
export VLLM_API_BASE="${VLLM_API_BASE:-http://localhost:8000/v1}"
export VLLM_API_KEY="${VLLM_API_KEY:-EMPTY}"
export GALAXY_API_BASE="${GALAXY_API_BASE:-https://token.ai-galaxy.com/v1}"
export OPENROUTER_API_BASE="${OPENROUTER_API_BASE:-https://openrouter.ai/api/v1}"
export GATEWAY_HOST="${GATEWAY_HOST:-127.0.0.1}"
export GATEWAY_PORT="${GATEWAY_PORT:-4000}"

# 2. litellm 检查
if [ ! -x .venv/bin/litellm ]; then
    echo "❌ 未检测到 litellm, 先运行 bash install.sh"
    exit 1
fi

# 3. 模型自动发现 (直连探测各上游 /models)
echo "▶ 生成模型清单 (直连探测)..."
./.venv/bin/python gateway/gen_local_models.py || true

# 4. 幂等: 已在运行且健康则跳过
if [ -f logs/gateway.pid ] && kill -0 "$(cat logs/gateway.pid)" 2>/dev/null; then
    if curl -sf -m 2 "http://$GATEWAY_HOST:$GATEWAY_PORT/health/liveliness" >/dev/null 2>&1; then
        echo "✅ 网关已在运行 (PID: $(cat logs/gateway.pid), $GATEWAY_HOST:$GATEWAY_PORT)"
        exit 0
    fi
    echo "⚠️  发现僵死网关进程, 清理后重启..."
    kill "$(cat logs/gateway.pid)" 2>/dev/null
    sleep 1
    pkill -9 -f "litellm --config gateway/" 2>/dev/null
    rm -f logs/gateway.pid
fi

# 5. 启动网关 (直连, 无代理)
echo "▶ 启动 litellm 网关 (直连模式)..."
nohup ./.venv/bin/litellm --config gateway/.litellm.runtime.yaml --host "$GATEWAY_HOST" --port "$GATEWAY_PORT" \
    >> logs/gateway.log 2>&1 &
echo $! > logs/gateway.pid

# 6. 等待就绪
for i in $(seq 1 30); do
    if curl -sf -m 2 "http://$GATEWAY_HOST:$GATEWAY_PORT/health/liveliness" >/dev/null 2>&1; then
        echo "✅ 网关已启动 (PID: $(cat logs/gateway.pid))"
        echo "   OpenAI 兼容端点: http://$GATEWAY_HOST:$GATEWAY_PORT/v1"
        echo "   模型清单: http://$GATEWAY_HOST:$GATEWAY_PORT/v1/models"
        echo "   冒烟: bash smoke.sh [--call]"
        exit 0
    fi
    sleep 2
done
echo "❌ 网关 60s 内未就绪, 查看日志: logs/gateway.log"
tail -20 logs/gateway.log
exit 1
