#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$ROOT_DIR/build/DeepSeek Harness.app"
URL="http://127.0.0.1:3080"

test -x "$APP_PATH/Contents/MacOS/DeepSeekHarnessDesktop"
test -f "$APP_PATH/Contents/Resources/dsh-agent-preset-advisor/package.json"
test -f "$APP_PATH/Contents/Resources/dsh-agent-preset-advisor/client.js"
plutil -lint "$APP_PATH/Contents/Info.plist"
codesign --verify --deep --strict "$APP_PATH"

printf 'App bundle metadata and signature are valid.\n'
printf 'Launch manually with: open %q\n' "$APP_PATH"
printf 'After launch, verify the embedded UI at %s and quit the app to verify child cleanup.\n' "$URL"
