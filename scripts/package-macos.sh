#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_PATH="$BUILD_DIR/DeepSeek Harness.app"
ZIP_PATH="$BUILD_DIR/DeepSeek-Harness-Desktop-0.0.1-macos.zip"

mkdir -p "$BUILD_DIR"
CACHE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/deepseek-harness-swift-cache.XXXXXX")"
trap 'rm -rf "$CACHE_ROOT"' EXIT
mkdir -p "$CACHE_ROOT/clang"
export CLANG_MODULE_CACHE_PATH="$CACHE_ROOT/clang"
export SWIFT_MODULECACHE_OVERRIDE="$CACHE_ROOT/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$CACHE_ROOT/clang"
swift build --package-path "$ROOT_DIR" -c release --disable-sandbox
BIN_PATH="$(swift build --package-path "$ROOT_DIR" -c release --disable-sandbox --show-bin-path)/DeepSeekHarnessDesktop"

rm -rf "$APP_PATH" "$ZIP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BIN_PATH" "$APP_PATH/Contents/MacOS/DeepSeekHarnessDesktop"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
chmod 0755 "$APP_PATH/Contents/MacOS/DeepSeekHarnessDesktop"

codesign --force --deep --sign - "$APP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

printf 'App: %s\n' "$APP_PATH"
printf 'Zip: %s\n' "$ZIP_PATH"
printf 'Binary: '
file "$APP_PATH/Contents/MacOS/DeepSeekHarnessDesktop"
