#!/bin/bash
# ============================================
# modelhub 环境安装: 建 .venv + 装 litellm[proxy]
# 用法:
#   bash install.sh                          # 自动挑 Python 3.9~3.12, pip 默认清华源
#   PYTHON=/path/to/python bash install.sh   # 指定解释器
#   PIP_INDEX_URL=https://pypi.org/simple bash install.sh   # 换 pip 源(需外网)
# ============================================
set -eu
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"
PIP_INDEX="${PIP_INDEX_URL:-https://pypi.tuna.tsinghua.edu.cn/simple}"

pick_python() {
    if [ -n "${PYTHON:-}" ]; then echo "$PYTHON"; return 0; fi
    for cand in python3.12 python3.11 python3.13 python3; do
        command -v "$cand" >/dev/null 2>&1 || continue
        v=$("$cand" -c 'import sys;print("%d.%d"%sys.version_info[:2])' 2>/dev/null) || continue
        case "$v" in
            3.11|3.12|3.13) echo "$cand"; return 0 ;;
        esac
    done
    return 1
}

PY=$(pick_python) || {
    echo "❌ 未找到 Python 3.11~3.13（litellm 1.98 需 3.11+; 3.14 依赖轮子不全）"
    echo "   请安装后重试, 或用 PYTHON=/path/to/python 指定"
    exit 1
}
echo "使用 Python: $PY ($($PY -V 2>&1))"

if [ ! -x .venv/bin/python ]; then
    "$PY" -m venv .venv
fi
./.venv/bin/pip install -U pip -i "$PIP_INDEX"
./.venv/bin/pip install -r requirements.txt -i "$PIP_INDEX"
VER=$(./.venv/bin/python -c 'import litellm; print(litellm.__version__)')
echo "✅ 安装完成: litellm $VER （.venv/bin/litellm）"
