#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="大肥鱼"
DEST="/Applications/$APP_NAME.app"

./build.sh

echo "▸ 退出正在运行的旧版本…"
osascript -e 'tell application "大肥鱼" to quit' 2>/dev/null || true
sleep 0.5

echo "▸ 安装到 $DEST …"
rm -rf "$DEST"
ditto "build/$APP_NAME.app" "$DEST"

echo "▸ 启动…"
open "$DEST"
echo "✓ 已安装并启动：$DEST"
