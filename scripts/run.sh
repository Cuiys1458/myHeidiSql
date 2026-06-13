#!/usr/bin/env bash
# 构建一个真正的 macOS .app bundle 并打开它。
# 第一次跑会触发 release 编译（首次 ~2 分钟），后续秒开。
#
#   ./scripts/run.sh           — 正常运行
#   ./scripts/run.sh --debug   — 用 debug 构建（编译快，运行略慢）
#   ./scripts/run.sh --clean   — 删除之前的 .app 和 .build 目录

set -euo pipefail

cd "$(dirname "$0")/.."

MODE="release"
CLEAN=0
for arg in "$@"; do
  case "$arg" in
    --debug) MODE="debug" ;;
    --clean) CLEAN=1 ;;
    *) echo "Unknown arg: $arg"; exit 2 ;;
  esac
done

if [[ "$CLEAN" -eq 1 ]]; then
  rm -rf .build MacHeidi.app
  echo "Cleaned .build/ and MacHeidi.app"
fi

echo "▶ Building MacHeidiApp ($MODE)..."
swift build -c "$MODE" --product MacHeidiApp

BIN="$(swift build -c "$MODE" --product MacHeidiApp --show-bin-path)/MacHeidiApp"
APP="MacHeidi.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"

rm -rf "$APP"
mkdir -p "$MACOS"
cp "$BIN" "$MACOS/MacHeidi"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                 <string>MacHeidi</string>
    <key>CFBundleDisplayName</key>          <string>MacHeidi</string>
    <key>CFBundleIdentifier</key>           <string>com.macheidi.app</string>
    <key>CFBundleExecutable</key>           <string>MacHeidi</string>
    <key>CFBundleVersion</key>              <string>0.1.0</string>
    <key>CFBundleShortVersionString</key>   <string>0.1.0</string>
    <key>CFBundlePackageType</key>          <string>APPL</string>
    <key>LSMinimumSystemVersion</key>       <string>14.0</string>
    <key>NSHighResolutionCapable</key>      <true/>
    <key>NSPrincipalClass</key>             <string>NSApplication</string>
</dict>
</plist>
PLIST

echo "▶ Launching $APP"
open "$APP"
echo "✓ App launched. PID: $(pgrep -n MacHeidi || echo 'not found yet')"
