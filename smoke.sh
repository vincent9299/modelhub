#!/bin/bash
# ============================================
# modelhub 冒烟测试
# 用法:
#   bash smoke.sh                        # 结构检查（代理链路+网关健康+模型清单, 零 LLM 花费）
#   bash smoke.sh --call                 # 结构检查 + 真实调用（默认本地与 Galaxy 两条）
#   bash smoke.sh --call M1,M2,...       # 指定要真实调用的模型名
# ============================================
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"
if [ -f .env ]; then set -a; . ./.env; set +a; fi
GATEWAY_HOST="${GATEWAY_HOST:-127.0.0.1}"
GATEWAY_PORT="${GATEWAY_PORT:-4000}"
PROXY_MIXED_PORT="${PROXY_MIXED_PORT:-7891}"
PROXY_API_PORT="${PROXY_API_PORT:-9091}"
BASE="http://$GATEWAY_HOST:$GATEWAY_PORT"
FAIL=0

note() { echo "── $*"; }
ok()   { echo "   ✅ $*"; }
bad()  { echo "   ❌ $*"; FAIL=1; }

note "1. 静态代理 (mihomo)"
V=$(curl -s -m 3 "http://127.0.0.1:$PROXY_API_PORT/version" 2>/dev/null)
[ -n "$V" ] && ok "mihomo API: $V" || bad "mihomo API 不可达 (127.0.0.1:$PROXY_API_PORT), 先 bash start.sh"

note "2. 静态链路验证 (openrouter.ai 应走 STATIC 组)"
( curl -s -m 20 -x "http://127.0.0.1:$PROXY_MIXED_PORT" -o /dev/null "https://openrouter.ai/api/v1/models" & ) >/dev/null 2>&1
CHAINS=""
for i in $(seq 1 12); do
    sleep 0.5
    CHAINS=$(curl -s -m 3 "http://127.0.0.1:$PROXY_API_PORT/connections" 2>/dev/null | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
hits = []
for c in (d.get("connections") or []):
    if "openrouter" in str((c.get("metadata") or {}).get("host", "")):
        hits.append(" > ".join(c.get("chains") or []))
print("; ".join(hits))' 2>/dev/null)
    [ -n "$CHAINS" ] && break
done
if [ -n "$CHAINS" ]; then
    case "$CHAINS" in
        *Static*) ok "openrouter 流量链路: $CHAINS" ;;
        *)        bad "openrouter 流量未命中 STATIC 组: $CHAINS" ;;
    esac
else
    bad "未捕捉到 openrouter 连接（请求可能失败, 看 logs/mihomo.log）"
fi
# 非 AI 流量: 对 modelhub 而言直连(继承宿主策略) —— 验证链路为 DIRECT, 且未误入 STATIC
( curl -s -m 8 -x "http://127.0.0.1:$PROXY_MIXED_PORT" -o /dev/null "https://api.ipify.org" & ) >/dev/null 2>&1
DCHAINS=""
for i in $(seq 1 12); do
    sleep 0.5
    DCHAINS=$(curl -s -m 3 "http://127.0.0.1:$PROXY_API_PORT/connections" 2>/dev/null | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
hits = []
for c in (d.get("connections") or []):
    if "ipify" in str((c.get("metadata") or {}).get("host", "")):
        hits.append(" > ".join(c.get("chains") or []))
print("; ".join(hits))' 2>/dev/null)
    [ -n "$DCHAINS" ] && break
done
if [ -n "$DCHAINS" ]; then
    case "$DCHAINS" in
        *Static*) bad "非 AI 流量被误路由进 STATIC 组: $DCHAINS" ;;
        *DIRECT*) ok "非 AI 流量 modelhub 视角直连 (继承宿主策略): $DCHAINS" ;;
        *)        note "非 AI 流量链路: $DCHAINS" ;;
    esac
else
    note "未捕捉到非 AI 连接（不影响 STATIC 链路判定）"
fi

note "3. 网关健康"
curl -sf -m 5 "$BASE/health/liveliness" >/dev/null && ok "liveliness OK" || bad "网关无响应 ($BASE)"
MODELS=$(curl -s -m 10 "$BASE/v1/models" 2>/dev/null)
IDS=$(printf '%s' "$MODELS" | grep -o '"id": *"[^"]*"' | sed 's/.*: *"//; s/"//' | tr '\n' ' ')
[ -n "$IDS" ] && ok "已注册模型: $IDS" || bad "模型清单为空（网关配置/密钥问题?）"

if [ "${1:-}" = "--call" ]; then
    note "4. 真实调用（各模型回一句话）"
    CALL_MODELS="${2:-qwen3.8-27b,qwen3.7-plus}"
    IFS=',' read -ra ARR <<< "$CALL_MODELS"
    for M in "${ARR[@]}"; do
        R=$(curl -s -m 120 "$BASE/v1/chat/completions" -H 'Content-Type: application/json' \
            -d "{\"model\":\"$M\",\"messages\":[{\"role\":\"user\",\"content\":\"只回复两个字: 收到\"}],\"max_tokens\":512}" 2>/dev/null)
        T=$(printf '%s' "$R" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    print(d["choices"][0]["message"]["content"].strip()[:60])
except Exception:
    print("__ERR__")' 2>/dev/null)
        if [ -n "$T" ] && [ "$T" != "__ERR__" ]; then
            ok "$M → $T"
        else
            bad "$M 调用失败: $(printf '%s' "$R" | head -c 200)"
        fi
    done
fi

echo
if [ $FAIL -eq 0 ]; then echo "✅ 冒烟全部通过"; else echo "❌ 存在失败项"; fi
exit $FAIL
