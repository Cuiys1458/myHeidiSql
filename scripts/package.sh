#!/usr/bin/env bash
# 打 release 版 .app + .dmg。
#
# 用法：./scripts/package.sh
#   产出：dist/MacHeidi-0.1.0.dmg
#
# 注意：未经 Apple Developer ID 签名 / 公证。第一次打开会被
# Gatekeeper 拦，需要：
#   - 右键 .app → 选 "打开" → 在弹窗里再点一次 "打开"
#   - 或：系统设置 → 隐私与安全 → 拉到底点 "仍要打开"

set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.1.0}"
APP_NAME="MacHeidi"
BUNDLE_ID="com.macheidi.app"
DIST_DIR="dist"
APP_PATH="$DIST_DIR/$APP_NAME.app"
DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"

echo "▶ Cleaning previous build…"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

echo "▶ Building release binary (universal: arm64 + x86_64)…"
# 单独编译两个架构再 lipo 合并，让 Intel + Apple Silicon 都能用
swift build -c release --arch arm64 --product "${APP_NAME}App"
ARM64_BIN="$(swift build -c release --arch arm64 --product "${APP_NAME}App" --show-bin-path)/${APP_NAME}App"

# x86_64 编译可能失败（依赖只编了 arm64 时），失败就只出 arm64 版
X86_BIN=""
if swift build -c release --arch x86_64 --product "${APP_NAME}App" 2>/dev/null; then
    X86_BIN="$(swift build -c release --arch x86_64 --product "${APP_NAME}App" --show-bin-path)/${APP_NAME}App"
    echo "  ✓ x86_64 build OK"
else
    echo "  ⚠ x86_64 build failed — producing arm64-only build"
fi

echo "▶ Creating .app bundle structure…"
CONTENTS="$APP_PATH/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
mkdir -p "$MACOS" "$RESOURCES"

# 合并 universal binary（如果两个架构都有）
if [[ -n "$X86_BIN" ]]; then
    lipo -create "$ARM64_BIN" "$X86_BIN" -output "$MACOS/$APP_NAME"
    echo "  ✓ Universal binary written"
else
    cp "$ARM64_BIN" "$MACOS/$APP_NAME"
    echo "  ✓ arm64 binary written"
fi
chmod +x "$MACOS/$APP_NAME"

# 拷贝资源（i18n 等）
SRC_BUNDLE="$(dirname "$ARM64_BIN")/${APP_NAME}_${APP_NAME}App.bundle"
if [[ -d "$SRC_BUNDLE" ]]; then
    cp -R "$SRC_BUNDLE" "$RESOURCES/"
    echo "  ✓ Resource bundle copied"
fi

# Info.plist
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                 <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>          <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>           <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>           <string>$APP_NAME</string>
    <key>CFBundleVersion</key>              <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>   <string>$VERSION</string>
    <key>CFBundlePackageType</key>          <string>APPL</string>
    <key>LSMinimumSystemVersion</key>       <string>14.0</string>
    <key>NSHighResolutionCapable</key>      <true/>
    <key>NSPrincipalClass</key>             <string>NSApplication</string>
    <key>LSApplicationCategoryType</key>    <string>public.app-category.developer-tools</string>
    <key>CFBundleIconFile</key>             <string>AppIcon</string>
</dict>
</plist>
PLIST

# 图标：如果 dist/AppIcon.icns 不存在就先生成
if [[ ! -f "$DIST_DIR/AppIcon.icns" ]]; then
    echo "▶ Generating App icon…"
    ./scripts/make-icon.sh >/dev/null 2>&1 || true
fi
if [[ -f "$DIST_DIR/AppIcon.icns" ]]; then
    cp "$DIST_DIR/AppIcon.icns" "$RESOURCES/AppIcon.icns"
    echo "  ✓ Icon embedded"
fi

# 临时打个 ad-hoc 签名让 macOS 能跑（非正式 Developer ID 签名）
echo "▶ Ad-hoc signing (no Developer ID — first launch needs right-click Open)…"
codesign --force --deep --sign - "$APP_PATH" 2>&1 | tail -3 || true

# 验证
if [[ ! -f "$MACOS/$APP_NAME" ]]; then
    echo "✗ App binary missing!" >&2
    exit 1
fi
APP_SIZE=$(du -sh "$APP_PATH" | awk '{print $1}')
echo "  ✓ $APP_PATH ($APP_SIZE)"

echo "▶ Creating .dmg…"
# 用 hdiutil 直接做一个简单 dmg：包含 .app + Applications 软链接，用户拖即装
STAGING="$DIST_DIR/dmg-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# 清理可能残留的旧 dmg
rm -f "$DMG_PATH"

hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

rm -rf "$STAGING"
DMG_SIZE=$(du -h "$DMG_PATH" | awk '{print $1}')

echo ""
echo "════════════════════════════════════════════════════════"
echo "✅ Done."
echo ""
echo "    📦 $DMG_PATH"
echo "    📏 $DMG_SIZE"
echo ""
echo "Install instructions:"
echo "  1. Double-click the .dmg"
echo "  2. Drag $APP_NAME.app to the Applications folder"
echo "  3. Open Applications, RIGHT-CLICK $APP_NAME → Open → Open"
echo "     (only needed first time — Gatekeeper bypass for unsigned apps)"
echo "════════════════════════════════════════════════════════"
