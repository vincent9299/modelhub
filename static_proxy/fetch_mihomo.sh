#!/bin/bash
# ============================================
# 下载 mihomo linux-amd64 二进制（版本与本机配置验证过的 v1.19.30 一致）
# 用法: bash static_proxy/fetch_mihomo.sh
# 说明: 下载源为 GitHub releases; 如所在机器访问 GitHub 困难,
#       先 export https_proxy=... 再跑本脚本; 或直接从旧机器拷贝
#       static_proxy/mihomo（二进制本身不入库）
# ============================================
set -eu
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VER="v1.19.30"
URL="https://github.com/MetaCubeX/mihomo/releases/download/${VER}/mihomo-linux-amd64-${VER}.gz"

echo "下载 $URL"
curl -fL --retry 3 -o "$DIR/mihomo.gz" "$URL"
gunzip -f "$DIR/mihomo.gz"
chmod +x "$DIR/mihomo"
"$DIR/mihomo" -v
echo "✅ mihomo 已就位: $DIR/mihomo"
