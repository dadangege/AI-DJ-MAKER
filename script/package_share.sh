#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_ROOT="$ROOT_DIR/dist"
DIST_DIR="$DIST_ROOT/SoulDJ-Share"
ZIP_PATH="$DIST_ROOT/SoulDJ-Share.zip"

pkill -x MiniMaxTTSStudio >/dev/null 2>&1 || true
if [ -e "$DIST_DIR" ]; then
  chmod -R u+w "$DIST_DIR" >/dev/null 2>&1 || true
fi
rm -rf "$DIST_DIR" "$ZIP_PATH"
mkdir -p "$DIST_DIR/macos"

rsync -a "$ROOT_DIR/macos/Soul DJ.app" "$DIST_DIR/macos/"

cat > "$DIST_DIR/README.md" <<'README'
# Soul DJ 分享版

## 第一次使用

1. 双击打开：

```text
macos/Soul DJ.app
```

2. 在 App 设置里填写自己的 OpenAI-compatible 配置：
   - API Key
   - Base URL，例如 `https://api.minimaxi.com/v1`
   - 文本模型，例如 `MiniMax-M2.7-highspeed`
   - TTS 模型，例如 `speech-2.8-hd`

3. 点击网易云扫码登录，选择歌单后播放。

## 注意

- 分享包不包含作者的 API Key、网易云 Cookie、下载音乐缓存和生成音频。
- 网易云扫码、歌单、歌词和播放地址解析已经内置在 Swift App 里，不需要安装 Node.js、Python 或额外脚本。
- 如果 macOS 提示无法打开，可以右键 App 选择“打开”。
- 当前构建是 Apple Silicon/arm64 版本，Intel Mac 可能无法运行。
README

(
  cd "$DIST_ROOT"
  ditto -c -k --sequesterRsrc --keepParent "SoulDJ-Share" "SoulDJ-Share.zip"
)

echo "Created: $DIST_DIR"
echo "Created: $ZIP_PATH"
