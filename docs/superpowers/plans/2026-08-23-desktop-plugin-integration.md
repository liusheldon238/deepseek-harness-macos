# Desktop Bundled Plugin and Self-Repair Implementation Plan

> Execute after both plugin `v0.1.0` releases exist. Use Swift tests first for every startup behavior change.

**Goal:** Ship DeepSeek Harness Desktop `v0.0.3` with both plugins pinned, bundled, installed idempotently, isolated on failure, and proven in a real installed DMG.

## Task 1: Pin independent plugin repositories

- Add the two GitHub repositories as submodules under `Resources/Plugins/` at released commits.
- Add a checked-in lock manifest with package name, version, commit, release URL, and SHA-256.
- Test/build scripts must fail on missing submodules or lock/package mismatch.
- Remove the old advisor resource and all installation references.
- Commit: `build: pin bundled dsh plugins`.

## Task 2: Architecture-safe runtime and bounded updates

- Add failing Swift tests for cached Node architecture validation, Node/npm/npx availability, update timeout/cancellation, and unchanged-version fast path.
- Require `process.arch` to match Apple Silicon `arm64` or Intel `x64`; automatically provision matching Node 22.23.1 on mismatch.
- Keep network checks bounded and cache current-version results so matching local DSH/plugins start immediately.
- Commit: `fix: harden runtime preparation`.

## Task 3: Idempotent install and old-advisor migration

- Add failing tests for ordered market/catalog/model installation, independent plugin failure reporting, repeated-start no-op, old advisor uninstall/disable, and complete manifest/lock/bundle rollback.
- Install from bundled `file:` snapshots into only the Desktop-owned profile using the app-owned architecture-matched Node.
- Verify installed package version and bundle activation marker after each operation.
- Commit: `feat: provision bundled dsh plugins`.

## Task 4: Precise conflict isolation and process ownership

- Add failing tests for exact bundle-to-package mapping, one-plugin disable/retry, rollback restoration, PID record validation, process-group creation before child execution, stale owned-process cleanup, and unrelated-process preservation.
- Put the child into its process group before it can spawn descendants; always terminate the verified owned group on stop/failure/app exit.
- Commit: `fix: make startup self-repair deterministic`.

## Task 5: Domain preflight, watchdog, and WebView recovery

- Add failing tests for root health plus `agentPreset.list` and `settings.describe` preflight, backend exit/health-loss recovery, cache-bypassing WebView reload, and inline log events.
- Only reveal WebView after domain preflight succeeds. On a named plugin conflict, disable only that plugin, log the cause in red, retry, and leave official capability usable.
- Commit: `fix: recover stale and unhealthy web sessions`.

## Task 6: Packaging and local installed acceptance

- Update README, screenshots/text, `Info.plist` to `0.0.3`, smoke tests, DMG layout, Applications symlink, icon, and release notes.
- Run full Swift tests, smoke test, app build, ad-hoc signing verification, DMG build, mount/copy into `/Applications`, and launch the installed app.
- Verify logs scroll naturally, shortcuts work, both plugins are installed/active, preset catalog search/install/default works, composer and `/model` search/select works, preset page/config open works, self-repair disables a deliberately broken plugin, and quit removes the owned DSH process.
- Download the published DMG, replace the installed app from that artifact, and repeat launch/critical-path acceptance.

## Task 7: Publish and independent review

- Push `main`, tag `v0.0.3`, publish DMG/ZIP/checksums and release notes.
- Independently review repository diff, release assets, clean checkout/submodules, tests, signature, installed version, running architecture, and process cleanup.
- Fix any blocker and rerun the full relevant verification before declaring completion.
