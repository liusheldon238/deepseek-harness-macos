# Self-Healing Startup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the macOS shell choose an architecture-correct Node runtime, update DSH and registry plugins safely, roll back failed updates, and isolate conflicting plugins until the Web UI starts.

**Architecture:** Add a core `StartupOrchestrator` that owns snapshots, metadata checks, per-plugin updates, conflict isolation, and DSH launch. Keep AppKit responsible only for progress/error presentation. Extend `DSHProcessManager` to accept a selected DSH package and validate the Web boot HTML, while preserving the existing app-owned profile.

**Tech Stack:** Swift 6, Foundation URLSession/Process, AppKit, existing DSH profile/PNPM workflow, XCTest.

## Global Constraints

- Apple Silicon accepts only arm64 Node; x86_64 Node is never used for DSH.
- Updates are best-effort; offline startup uses the last verified local versions.
- Every update is snapshotted before mutation and restored when health validation fails.
- User profile `~/.dsh` is never modified.
- Existing uncommitted user changes must be preserved.

### Task 1: Version metadata and snapshot primitives

**Files:**
- Create: `Sources/DeepSeekHarnessCore/SelfHealingStartup.swift`
- Modify: `Package.swift`
- Test: `Tests/DeepSeekHarnessCoreTests/SelfHealingStartupTests.swift`

- [ ] Add `RemotePackageVersion`, `StartupPhase`, `StartupSnapshot` and deterministic semver comparison.
- [ ] Add snapshot create/restore for `dsh-home/profiles/web/package.json`, `pnpm-lock.yaml`, `cordis.patch.yml`, and a disabled-plugin JSON file.
- [ ] Add tests for semver, missing files, restore, and snapshot cleanup.

### Task 2: DSH and plugin update orchestration

**Files:**
- Modify: `Sources/DeepSeekHarnessCore/SelfHealingStartup.swift`
- Modify: `Sources/DeepSeekHarnessCore/DSHProcessManager.swift`
- Test: `Tests/DeepSeekHarnessCoreTests/SelfHealingStartupTests.swift`

- [ ] Query npm metadata for `@deepseek-ai/dsh` with a bounded timeout and use cached package when offline.
- [ ] Enumerate profile dependencies; skip `file:` dependencies and built-in `@deepseek-ai/dsh-*` layers, update registry plugins one at a time with `pnpm update --latest`.
- [ ] Pass the chosen DSH spec to `DSHProcessManager` instead of hard-coding rc.6.
- [ ] Validate the HTML body after HTTP 200 and return the reported failing plugin entry when it contains `Failed to load plugins` or `web boot:`.

### Task 3: Conflict isolation and rollback

**Files:**
- Modify: `Sources/DeepSeekHarnessCore/SelfHealingStartup.swift`
- Test: `Tests/DeepSeekHarnessCoreTests/SelfHealingStartupTests.swift`

- [ ] Maintain a core-plugin allowlist; never disable core DSH layers.
- [ ] Remove only third-party entries from `dsh.profile.bundles`, record them in the disabled-plugin JSON, restart, and retry health validation.
- [ ] Restore the snapshot when all candidates fail, returning a report with conflict names, disabled names, and rollback status.

### Task 4: App startup UI and documentation

**Files:**
- Modify: `Sources/DeepSeekHarnessDesktop/ShellViewController.swift`
- Modify: `README.md`
- Modify: `scripts/smoke-test.sh`

- [ ] Replace the fixed startup messages with orchestrator phase progress.
- [ ] Show architecture, update result, disabled plugins, rollback status, and selectable red logs on failure.
- [ ] Add smoke checks for the self-healing metadata and arm64 selection behavior.

### Task 5: Verification and release

- [ ] Run Swift tests and `node --check` for bundled client assets.
- [ ] Run a temporary `DSH_HOME` update/install/start smoke test with a real `file:` advisor plugin.
- [ ] Build, ad-hoc sign, ZIP, DMG, launch locally, verify HTTP 200 and process cleanup.
- [ ] Commit only implementation changes, push, and update the existing `v0.0.1` assets after verification.
