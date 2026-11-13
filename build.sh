#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="大肥鱼"
EXEC="DaFeiYu"
OUT="build"
SDK="$(xcrun --show-sdk-path)"
CACHE="$PWD/.build/modulecache"
mkdir -p "$CACHE"

echo "▸ 清理…"
rm -rf "$OUT/$APP_NAME.app"
mkdir -p "$OUT/$APP_NAME.app/Contents/MacOS"
mkdir -p "$OUT/$APP_NAME.app/Contents/Resources"

echo "▸ 编译 Swift（arm64, macOS 14+）…"
swiftc \
  -O -whole-module-optimization \
  -swift-version 5 \
  -target arm64-apple-macos14.0 \
  -sdk "$SDK" \
  -module-cache-path "$CACHE" \
  -framework AppKit \
  -framework SwiftUI \
  -framework Carbon \
  -framework Speech \
  -framework AVFoundation \
  -framework Security \
  Sources/*.swift \
  -o "$OUT/$APP_NAME.app/Contents/MacOS/$EXEC"

echo "▸ 组装 App Bundle…"
cp Resources/Info.plist "$OUT/$APP_NAME.app/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$OUT/$APP_NAME.app/Contents/Resources/AppIcon.icns"
fi
if [ -d Resources/Skills ]; then
  cp -R Resources/Skills "$OUT/$APP_NAME.app/Contents/Resources/"
fi

echo "▸ 阿黑签名（ad-hoc，暂存到临时目录避开 Finder 扩展属性）…"
STAGE="$(mktemp -d)/$APP_NAME.app"
ditto "$OUT/$APP_NAME.app" "$STAGE"
xattr -cr "$STAGE"
codesign --force --deep --sign - --identifier com.liukai.dafeiyu "$STAGE"
rm -rf "$OUT/$APP_NAME.app"
ditto "$STAGE" "$OUT/$APP_NAME.app"
rm -rf "$(dirname "$STAGE")"

echo "▸ 完成：$OUT/$APP_NAME.app"
du -sh "$OUT/$APP_NAME.app"
