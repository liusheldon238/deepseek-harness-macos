#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="${DSH_APP_PATH:-$ROOT_DIR/build/DeepSeek Harness.app}"
PLIST_PATH="$APP_PATH/Contents/Info.plist"
BIN_PATH="$APP_PATH/Contents/MacOS/DeepSeekHarnessDesktop"
ADVISOR_DIR="$APP_PATH/Contents/Resources/dsh-agent-preset-advisor"
LOG_PATH="$HOME/Library/Application Support/DeepSeek Harness Desktop/dsh.log"
URL_PATTERN='dsh web: http://127\.0\.0\.1:[0-9]+'

if [[ ! -d "$APP_PATH" ]]; then
  printf 'ERROR: app bundle not found at %s\nRun ./scripts/package-macos.sh first.\n' "$APP_PATH" >&2
  exit 1
fi

# Bundle structure: executable bit, icon, and the bundled advisor plugin.
test -x "$BIN_PATH"
test -f "$APP_PATH/Contents/Resources/AppIcon.icns"
test -f "$ADVISOR_DIR/package.json"
test -f "$ADVISOR_DIR/index.js"
test -f "$ADVISOR_DIR/client.js"
test -f "$ADVISOR_DIR/cordis.patch.yml"

# Plist lint and key/value consistency.
plutil -lint "$PLIST_PATH"

VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$PLIST_PATH" 2>/dev/null || true)"
[[ -n "$VERSION" ]] || { printf 'ERROR: CFBundleShortVersionString missing from %s\n' "$PLIST_PATH" >&2; exit 1; }

BUNDLE_EXECUTABLE="$(plutil -extract CFBundleExecutable raw -o - "$PLIST_PATH" 2>/dev/null || true)"
[[ "$BUNDLE_EXECUTABLE" = "$(basename "$BIN_PATH")" ]] || {
  printf 'ERROR: CFBundleExecutable (%s) does not match the bundled binary %s\n' "${BUNDLE_EXECUTABLE:-<missing>}" "$BIN_PATH" >&2
  exit 1
}

ICON_FILE="$(plutil -extract CFBundleIconFile raw -o - "$PLIST_PATH" 2>/dev/null || true)"
[[ "$ICON_FILE" = "AppIcon.icns" ]] || {
  printf 'ERROR: CFBundleIconFile (%s) does not reference the bundled AppIcon.icns\n' "${ICON_FILE:-<missing>}" >&2
  exit 1
}

# Signature check.
codesign --verify --deep --strict "$APP_PATH"

printf 'Smoke test passed for DeepSeek Harness Desktop %s.\n' "$VERSION"
printf 'Bundle structure, plist, bundled advisor plugin, and code signature are valid.\n'
printf '\nManual verification — the app starts dsh web with --port 0, so the port is OS-selected at every launch:\n'
printf '  1. open %q\n' "$APP_PATH"
printf '  2. Wait for the embedded UI to load, then check the generated log for the dsh web URL:\n'
printf '     grep -E %q %q\n' "$URL_PATTERN" "$LOG_PATH"
printf '     Expect a line like: dsh web: http://127.0.0.1:<port>\n'
printf '  3. Confirm the app window shows the page served at that http://127.0.0.1:<port> URL.\n'
printf '  4. Quit the app (Cmd+Q) and verify the DSH child process exited:\n'
printf '     pgrep -fl %q  (should print nothing)\n' '@deepseek-ai/dsh'
