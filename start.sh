#!/bin/bash
# ============================================
# modelhub 一键启动: 静态代理(幂等) + LiteLLM 网关
# 用法: bash start.sh
# 停止: bash stop.sh          # 只停网关
#       bash stop.sh --all    # 网关 + 静态代理一起停
# ============================================
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"
mkdir -p logs

# 1. 加载 .env（密钥与可选配置; 不存在则用默认值继续）
if [ -f .env ]; then
    set -a; . ./.env; set +a
else
    echo "⚠️  未找到 .env, 按默认值继续（参考 .env.example 创建）"
fi
export VLLM_API_BASE="${VLLM_API_BASE:-http://localhost:8000/v1}"
export VLLM_API_KEY="${VLLM_API_KEY:-EMPTY}"
export GALAXY_API_BASE="${GALAXY_API_BASE:-https://token.ai-galaxy.com/v1}"
export OPENROUTER_API_BASE="${OPENROUTER_API_BASE:-https://openrouter.ai/api/v1}"
export GATEWAY_HOST="${GATEWAY_HOST:-127.0.0.1}"
export GATEWAY_PORT="${GATEWAY_PORT:-4000}"
# 端口单一来源: static_proxy/config.yaml 的 mixed-port（mihomo 实际监听处）,
# 不从 .env 读——两个定义处必然漂移, 漂移即全部外发上游静默 Connection error
PROXY_MIXED_PORT=$(awk '/^mixed-port:/{print $2; exit}' static_proxy/config.yaml 2>/dev/null)
PROXY_MIXED_PORT="${PROXY_MIXED_PORT:-7891}"

# 2. 静态代理（幂等; 已在运行则跳过）
bash static_proxy/start.sh || exit 1

# 3. 网关环境检查（未装则先装）
if [ ! -x .venv/bin/litellm ]; then
    echo "ℹ️  未检测到 litellm, 先运行 install.sh ..."
    bash install.sh || exit 1
fi

# 3.5 进程级代理注入: 必须在模型发现之前——OpenRouter 等外网上游的 /models
#     探测要走 mihomo 分流（直连不通）; 网关进程外发流量同样按域名分流
#    （AI API 域名 → STATIC 静态出口, 名单见 static_proxy/config.yaml;
#      其余上游对 modelhub 而言直连, 宿主机策略自行叠加, modelhub 不感知）
#    no_proxy 保证本地 vLLM 与 Galaxy 专线直连, 不绕代理
unset all_proxy ALL_PROXY
# litellm 的 --debug/--detailed_debug 旗标绑定同名环境变量,
# 宿主环境残留的 DEBUG=* 值(如 'release')会让 CLI 解析直接报错, 启动前清掉
unset DEBUG DETAILED_DEBUG
export http_proxy="http://127.0.0.1:${PROXY_MIXED_PORT}"
export https_proxy="http://127.0.0.1:${PROXY_MIXED_PORT}"
GALAXY_HOST=$(printf '%s' "$GALAXY_API_BASE" | sed -E 's|https?://([^/:]+).*|\1|')
VLLM_HOST=$(printf '%s' "$VLLM_API_BASE" | sed -E 's|https?://([^/:]+).*|\1|')
export no_proxy="localhost,127.0.0.1,${GALAXY_HOST},${VLLM_HOST},192.168.10.0/24,100.64.0.0/10"

# 4. 模型自动发现: 探测各 *_API_BASE 端点的 /models 列表（含 OpenRouter 全量展开）,
#    并入配置生成 gateway/.litellm.runtime.yaml（凭据仍走 env 注入）
./.venv/bin/python gateway/gen_local_models.py || true

# 5. 幂等: 网关已在运行（pid 活着且健康才跳过; pid 活但不健康 = 僵死, 清理后重启）
if [ -f logs/gateway.pid ] && kill -0 "$(cat logs/gateway.pid)" 2>/dev/null; then
    if curl -sf -m 2 "http://$GATEWAY_HOST:$GATEWAY_PORT/health/liveliness" >/dev/null 2>&1; then
        echo "✅ 网关已在运行 (PID: $(cat logs/gateway.pid), $GATEWAY_HOST:$GATEWAY_PORT)"
        exit 0
    fi
    echo "⚠️  发现僵死网关进程 (PID $(cat logs/gateway.pid)), 清理后重启..."
    kill "$(cat logs/gateway.pid)" 2>/dev/null
    sleep 1
    pkill -9 -f "litellm --config gateway/" 2>/dev/null
    rm -f logs/gateway.pid
fi

# 6. 启动网关
nohup ./.venv/bin/litellm --config gateway/.litellm.runtime.yaml --host "$GATEWAY_HOST" --port "$GATEWAY_PORT" \
    >> logs/gateway.log 2>&1 &
echo $! > logs/gateway.pid

# 7. 等待就绪（litellm 首次启动较慢, 给足 60s）
for i in $(seq 1 30); do
    if curl -sf -m 2 "http://$GATEWAY_HOST:$GATEWAY_PORT/health/liveliness" >/dev/null 2>&1; then
        echo "✅ 网关已启动 (PID: $(cat logs/gateway.pid))"
        echo "   OpenAI 兼容端点: http://$GATEWAY_HOST:$GATEWAY_PORT/v1"
        echo "   模型清单(含自动发现): http://$GATEWAY_HOST:$GATEWAY_PORT/v1/models"
        echo "   出口: AI API 域名 → 静态出口; 其余直连(继承宿主策略)"
        echo "   冒烟: bash smoke.sh [--call]"
        exit 0
    fi
    sleep 2
done
echo "❌ 网关 60s 内未就绪, 查看日志: logs/gateway.log"
tail -20 logs/gateway.log
exit 1
