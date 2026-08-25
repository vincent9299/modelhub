#!/bin/bash
# ============================================
# 下载 mihomo 二进制（版本与本机配置验证过的 v1.19.30 一致）
# 用法: bash static_proxy/fetch_mihomo.sh
# 说明: 自动识别 Linux/macOS × amd64/arm64, 下对应平台的 mihomo;
#       下载源为 GitHub releases; 如所在机器访问 GitHub 困难,
#       先 export https_proxy=... 再跑本脚本; 或直接从旧机器拷贝
#       static_proxy/mihomo（二进制本身不入库）
# ============================================
set -eu
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VER="v1.19.30"

# ---- 平台/架构识别 ----
OS=$(uname -s | tr '[:upper:]' '[:lower:]')       # linux / darwin
ARCH=$(uname -m)                                   # x86_64 / arm64
[ "$ARCH" = "x86_64" ] && ARCH="amd64"
[ "$ARCH" = "aarch64" ] && ARCH="arm64"
if [ "$OS" != "linux" ] && [ "$OS" != "darwin" ]; then
    echo "❌ 不支持的平台: $OS-$ARCH（仅支持 linux/darwin × amd64/arm64）" >&2
    exit 1
fi

URL="https://github.com/MetaCubeX/mihomo/releases/download/${VER}/mihomo-${OS}-${ARCH}-${VER}.gz"
echo "平台: $OS-$ARCH"
echo "下载 $URL"
curl -fL --retry 3 -o "$DIR/mihomo.gz" "$URL"
gunzip -f "$DIR/mihomo.gz"
chmod +x "$DIR/mihomo"
"$DIR/mihomo" -v
echo "✅ mihomo 已就位: $DIR/mihomo"
