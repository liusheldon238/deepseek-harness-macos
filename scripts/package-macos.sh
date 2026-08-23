#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_PATH="$BUILD_DIR/DeepSeek Harness.app"
VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$ROOT_DIR/Resources/Info.plist" 2>/dev/null || true)"
if [[ -z "$VERSION" || ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf 'Warning: could not read CFBundleShortVersionString from Resources/Info.plist; falling back to 0.0.1\n' >&2
  VERSION="0.0.1"
fi
ZIP_PATH="$BUILD_DIR/DeepSeek-Harness-Desktop-${VERSION}-macos.zip"
DMG_PATH="$BUILD_DIR/DeepSeek-Harness-Desktop-${VERSION}-macos.dmg"

mkdir -p "$BUILD_DIR"
CACHE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/deepseek-harness-swift-cache.XXXXXX")"
trap 'rm -rf "$CACHE_ROOT"' EXIT
mkdir -p "$CACHE_ROOT/clang"
export CLANG_MODULE_CACHE_PATH="$CACHE_ROOT/clang"
export SWIFT_MODULECACHE_OVERRIDE="$CACHE_ROOT/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$CACHE_ROOT/clang"
swift build --package-path "$ROOT_DIR" -c release --disable-sandbox
BIN_PATH="$(swift build --package-path "$ROOT_DIR" -c release --disable-sandbox --show-bin-path)/DeepSeekHarnessDesktop"
test -x "$BIN_PATH" || { printf 'ERROR: built binary not found at %s\n' "$BIN_PATH" >&2; exit 1; }

rm -rf "$APP_PATH" "$ZIP_PATH" "$DMG_PATH"
rm -f "$BUILD_DIR"/DeepSeek-Harness-Desktop-*-macos.zip "$BUILD_DIR"/DeepSeek-Harness-Desktop-*-macos.dmg
ICON_TMP="$(mktemp -d "${TMPDIR:-/tmp}/deepseek-harness-icon.XXXXXX")"
trap 'rm -rf "$CACHE_ROOT" "$ICON_TMP"' EXIT
qlmanage -t -s 1024 -o "$ICON_TMP" "$ROOT_DIR/Resources/deepseek-whale.svg" >/dev/null
sips --resampleHeightWidth 1024 1024 "$ICON_TMP/deepseek-whale.svg.png" --out "$ICON_TMP/icon.png" >/dev/null
ICONSET="$ICON_TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips --resampleHeightWidth "$size" "$size" "$ICON_TMP/icon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips --resampleHeightWidth "$retina" "$retina" "$ICON_TMP/icon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ICON_TMP/AppIcon.icns"

mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BIN_PATH" "$APP_PATH/Contents/MacOS/DeepSeekHarnessDesktop"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$ICON_TMP/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
cp -R "$ROOT_DIR/Resources/dsh-agent-preset-advisor" "$APP_PATH/Contents/Resources/dsh-agent-preset-advisor"
chmod 0755 "$APP_PATH/Contents/MacOS/DeepSeekHarnessDesktop"

codesign --force --deep --sign - "$APP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
DMG_STAGE="$ICON_TMP/dmg-stage"
mkdir -p "$DMG_STAGE"
cp -R "$APP_PATH" "$DMG_STAGE/DeepSeek Harness.app"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create -volname "DeepSeek Harness Desktop" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG_PATH" >/dev/null

printf 'Version: %s\n' "$VERSION"
printf 'App: %s\n' "$APP_PATH"
printf 'Zip: %s\n' "$ZIP_PATH"
printf 'Dmg: %s\n' "$DMG_PATH"
printf 'Binary: '
file "$APP_PATH/Contents/MacOS/DeepSeekHarnessDesktop"
