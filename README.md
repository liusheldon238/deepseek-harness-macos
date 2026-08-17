# DeepSeek Harness Desktop

Native macOS shell for [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness). It starts the local DSH Web UI in the background and displays it inside a native `WKWebView` window.

## What it does

- Scans PATH, Homebrew, and common Node.js locations.
- Uses an existing Node.js only when it is at least `22.19.0` and matches the host CPU architecture.
- Downloads Node.js `22.23.1` for Apple Silicon or Intel when the local environment is missing or incompatible.
- Verifies the official Node archive SHA-256 before extraction.
- Starts `@deepseek-ai/dsh@0.1.0-rc.6` on loopback with an OS-selected free port.
- Waits for an HTTP 200 response before loading the page in the app window.
- Stops the DSH child process when the app exits.

Runtime files are stored in `~/Library/Application Support/DeepSeek Harness Desktop/`. No administrator access is required.

## Build

Requirements: macOS 13+, Xcode 26 or Swift 6, and network access on first launch if Node.js is not already available.

```bash
swift test
./scripts/package-macos.sh
./scripts/smoke-test.sh
open "build/DeepSeek Harness.app"
```

The package script creates an ad-hoc signed app, a ZIP, and a drag-to-Applications DMG at `build/DeepSeek-Harness-Desktop-0.0.1-macos.dmg`. The app icon is derived from the official DeepSeek logo asset in [deepseek-ai/DeepSeek-V2](https://github.com/deepseek-ai/DeepSeek-V2/blob/main/figures/logo.svg). An Apple Developer signing identity is required for a notarized distribution; otherwise macOS may require a one-time manual approval on first launch.

## Development

The core runtime and process code is in `Sources/DeepSeekHarnessCore`. The AppKit/WebKit shell is in `Sources/DeepSeekHarnessDesktop`.

DeepSeek Harness is a developer preview and may introduce compatibility-breaking changes. The DSH package version is pinned in the process manager for reproducible startup.

## License

This wrapper is released under the MIT License. DeepSeek Harness and its dependencies retain their own licenses.
