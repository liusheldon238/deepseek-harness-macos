#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOCK_PATH="$ROOT_DIR/Resources/Plugins/plugins.lock.json"

test -f "$LOCK_PATH" || { printf 'ERROR: missing %s\n' "$LOCK_PATH" >&2; exit 1; }

plugin_rows="$(/usr/bin/python3 - "$LOCK_PATH" <<'PY'
import json
import re
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    lock = json.load(handle)
plugins = lock.get("plugins", [])
expected = ["dsh-preset-catalog", "dsh-model-search"]
if lock.get("schemaVersion") != 1 or [plugin.get("packageName") for plugin in plugins] != expected:
    raise SystemExit("ERROR: plugins.lock.json must contain the two schemaVersion 1 plugins in installation order")
for plugin in plugins:
    fields = ("packageName", "version", "path", "commit", "releaseURL", "releaseAssetURL", "releaseAssetSHA256")
    if any(not isinstance(plugin.get(field), str) or not plugin[field] for field in fields):
        raise SystemExit("ERROR: plugins.lock.json contains an incomplete plugin entry")
    if not re.fullmatch(r"[0-9a-f]{40}", plugin["commit"]):
        raise SystemExit(f"ERROR: {plugin['packageName']} commit is invalid")
    if not re.fullmatch(r"[0-9a-f]{64}", plugin["releaseAssetSHA256"]):
        raise SystemExit(f"ERROR: {plugin['packageName']} release SHA-256 is invalid")
    print("\t".join(plugin[field] for field in ("packageName", "version", "path", "commit", "releaseAssetSHA256")))
PY
)"

while IFS=$'\t' read -r package_name version relative_path commit sha256; do
  plugin_path="$ROOT_DIR/Resources/Plugins/$relative_path"
  test -f "$plugin_path/package.json" || { printf 'ERROR: submodule %s is missing or not initialized\n' "$relative_path" >&2; exit 1; }
  actual_commit="$(git -C "$plugin_path" rev-parse HEAD 2>/dev/null || true)"
  [[ "$actual_commit" = "$commit" ]] || { printf 'ERROR: %s commit %s does not match lock %s\n' "$package_name" "${actual_commit:-<missing>}" "$commit" >&2; exit 1; }
  git -C "$plugin_path" diff --quiet --ignore-submodules=none || { printf 'ERROR: bundled plugin %s has uncommitted changes\n' "$package_name" >&2; exit 1; }
  actual_name="$(plutil -extract name raw -o - "$plugin_path/package.json")"
  actual_version="$(plutil -extract version raw -o - "$plugin_path/package.json")"
  [[ "$actual_name" = "$package_name" ]] || { printf 'ERROR: %s package name is %s\n' "$relative_path" "$actual_name" >&2; exit 1; }
  [[ "$actual_version" = "$version" ]] || { printf 'ERROR: %s version %s does not match lock %s\n' "$package_name" "$actual_version" "$version" >&2; exit 1; }
  test -f "$plugin_path/index.js"
  test -f "$plugin_path/client.js"
  test -f "$plugin_path/cordis.patch.yml"
done <<< "$plugin_rows"

printf 'Bundled plugin lock verified.\n'
