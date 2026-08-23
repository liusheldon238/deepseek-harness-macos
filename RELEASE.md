# Releasing DeepSeek Harness Desktop

Checklist for cutting a release. Current release candidate: **v0.0.3**.

## Version source of truth

There is no separate version manifest. The single source of truth is `Resources/Info.plist`:

- `CFBundleShortVersionString` — the release version (currently `0.0.3`). `scripts/package-macos.sh` reads this key to name the ZIP/DMG artifacts and fails if it is malformed.
- `CFBundleVersion` — the build number; increment on every release (currently `3`).

`Package.swift` intentionally carries no version; it only pins the Swift tools version, the macOS deployment target, and the target layout.

## Release checklist

1. **Test**
   ```bash
   swift test
   ```
   All unit tests must pass.

2. **Package**
   ```bash
   chmod +x scripts/package-macos.sh scripts/smoke-test.sh   # only if the executable bit was lost
   ./scripts/package-macos.sh
   ```
   Produces (version read from `Resources/Info.plist`):
   - `build/DeepSeek Harness.app`
   - `build/DeepSeek-Harness-Desktop-<version>-macos.zip`
   - `build/DeepSeek-Harness-Desktop-<version>-macos.dmg`

3. **Smoke test**
   ```bash
   ./scripts/smoke-test.sh
   ```
   Verifies the bundle structure (executable bit, icon, pinned preset/model plugins and lock), plist key consistency, and the code signature. Then follow its printed manual steps: launch the app, confirm both plugins are installed and active, read the generated log for `dsh web: http://127.0.0.1:<port>`, confirm the embedded UI loads, and quit the app to verify the owned DSH child process is cleaned up.

4. **Commit and tag**
   ```bash
   git add -A
   git commit -m "Release v0.0.3"
   git tag v0.0.3
   ```

5. **Push**
   ```bash
   git push origin main --tags
   ```

6. **GitHub release**
   - Create a new release on GitHub for the `v0.0.3` tag.
   - Attach `build/DeepSeek-Harness-Desktop-0.0.3-macos.dmg` and `build/DeepSeek-Harness-Desktop-0.0.3-macos.zip` to the release.
   - Note in the release body that the app is ad-hoc signed, so macOS may require a one-time manual approval on first launch; an Apple Developer identity is needed for notarized distribution.

For the next release: bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`, update the version references in `README.md` and this file, then repeat this checklist.
