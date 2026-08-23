# DeepSeek Harness Desktop

<p align="center">
  <img src="Resources/deepseek-logo.svg" alt="DeepSeek" width="360">
</p>

Native macOS shell for [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness). It starts the local DSH Web UI in the background and displays it inside a native `WKWebView` window.

## What it does

- Scans PATH, Homebrew, and common Node.js locations.
- Uses an existing Node.js only when it is at least `22.19.0` and matches the host CPU architecture.
- Downloads Node.js `22.23.1` for Apple Silicon or Intel when the local environment is missing or incompatible.
- Verifies the official Node archive SHA-256 before extraction.
- Checks GitHub and npm, keeps the newest compatible local DSH, and starts it on loopback with an OS-selected free port (`0.1.0-rc.6` is only the offline fallback).
- Initializes the app-owned web profile and installs `dshmarket@1.13.1` on first launch, so the DSH Web UI includes a plugin marketplace for browsing, installing, updating, disabling, and removing other plugins.
- Installs the pinned `dsh-preset-catalog` and `dsh-model-search` snapshots from `Resources/Plugins` in that order. The catalog provides searchable domain presets; model search improves composer and `/model` selection while preserving raw model IDs.
- On every launch, verifies that Node matches the host architecture (Apple Silicon uses arm64 only), checks the latest DeepSeek Harness release, updates registry plugins one at a time, snapshots the profile, and rolls back failed updates.
- If the Web UI reports a plugin boot conflict, automatically isolates third-party plugin layers one at a time, retries startup, and shows the conflict and disabled-plugin list in the red inline log.
- Requires the root page plus `agentPreset.list` and `settings.describe` RPC checks before loading the page, then continuously watches backend health and reloads without stale WebView cache after recovery.
- Stops the DSH child process when the app exits.

Runtime files are stored in `~/Library/Application Support/DeepSeek Harness Desktop/`. No administrator access is required.

The isolated DSH profile is stored below `dsh-home/profiles/web`; it does not modify the user's default `~/.dsh` profile. The market, preset catalog, and model search packages are installed idempotently. A missing dependency, installed package, version, or bundle activation marker triggers repair on the next cold launch. Offline startup uses the last verified local versions.

## Build

Requirements: macOS 13+, Xcode 26 or Swift 6, and network access on first launch if Node.js is not already available.

```bash
chmod +x scripts/package-macos.sh scripts/smoke-test.sh   # only if the executable bit was lost
swift test
./scripts/package-macos.sh
./scripts/smoke-test.sh
open "build/DeepSeek Harness.app"
```

The package script verifies the submodule commits and `plugins.lock.json`, then creates an ad-hoc signed app, a ZIP, and a drag-to-Applications DMG in `build/`. Artifact names embed version `0.0.3`: `build/DeepSeek-Harness-Desktop-0.0.3-macos.zip` and `build/DeepSeek-Harness-Desktop-0.0.3-macos.dmg`. The smoke test validates the bundle, both pinned plugins, plist, and code signature; because the app starts DSH with `--port 0`, the real port is OS-selected and appears in the generated log as `dsh web: http://127.0.0.1:<port>`. The app icon is derived from the official DeepSeek logo asset in [deepseek-ai/DeepSeek-V2](https://github.com/deepseek-ai/DeepSeek-V2/blob/main/figures/logo.svg). An Apple Developer signing identity is required for a notarized distribution; otherwise macOS may require a one-time manual approval on first launch.

## Release

Cutting a release is a checklist: run the tests, package, smoke test, tag `v0.0.3`, push `origin main --tags`, then attach the DMG and ZIP to the GitHub release. See [RELEASE.md](RELEASE.md) for the full step-by-step procedure.

## Development

The core runtime and process code is in `Sources/DeepSeekHarnessCore`. The AppKit/WebKit shell is in `Sources/DeepSeekHarnessDesktop`.

DeepSeek Harness is a developer preview and may introduce compatibility-breaking changes. The DSH package version is pinned in the process manager for reproducible startup.

## License

This wrapper is released under the MIT License. DeepSeek Harness and its dependencies retain their own licenses.
