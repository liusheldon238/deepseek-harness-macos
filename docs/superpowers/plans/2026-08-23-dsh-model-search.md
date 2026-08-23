# dsh-model-search Implementation Plan

> Execute with test-driven development. Keep official model selection and its click/RPC handlers authoritative.

**Goal:** Publish an MIT-licensed DSH client plugin that searches composer and `/model` choices by provider, display name, and raw model ID.

**Repository:** `/Users/mars/Documents/小说/dsh-model-search` -> `liusheldon238/dsh-model-search`

**Release:** `v0.1.0`

## Task 1: Pure filtering core

Create `package.json`, `LICENSE`, `README.md`, `index.js`, `client.js`, `cordis.patch.yml`, `lib/filter.js`, and `test/filter.test.js`.

- Test first: case-insensitive continuous substring matching for provider name/ID and model name/ID; empty query; Unicode names; empty groups; deterministic original ordering.
- Implement only pure filtering/normalization needed to pass.
- Commit: `feat: add model filtering core`.

## Task 2: Directory-backed DOM mapping

Create `lib/directory.js`, `lib/dom.js`, `test/directory.test.js`, and `test/dom.test.js` with jsdom fixtures.

- Test first: current-session rebinding; group/model structural index mapping; duplicate display names; strict count/order mismatch no-op; provider failure rows; cleanup/unsubscribe.
- Use public `sessions.list` and `modelDirectories.directoryFor(sessionId).store`; never infer raw IDs from visible labels.
- Root inject only requires `sessions`; optional `modelDirectories` is acquired through `ctx.inject()` so older DSH can boot with a no-op plugin.
- Commit: `feat: map official model rows safely`.

## Task 3: Composer decorator

- Test first: identify semantic menu roles/labels, inject once, focus search, hide unmatched original rows and empty groups, restore on clear/unmount, keyboard up/down/Enter, two-stage Escape, localized empty state, and incompatible DOM warning-once fallback.
- Preserve original row nodes and call their existing `.click()` handlers; never clone or issue selection RPCs.
- Commit: `feat: enhance composer model search`.

## Task 4: `/model` decorator

- Test first: identify `/model` popup by accessible label, neutralize the native label-only filter, add raw-ID-aware input, preserve option nodes/controller/token consumption, keyboard behavior, and cleanup.
- Keep native search state blank so it does not remove rows before raw-ID matching.
- Commit: `feat: enhance model command search`.

## Task 5: Integration, publication, and acceptance

- Run `npm ci`, `npm test`, `npm pack --dry-run`, and install tarball into a temporary DSH home.
- Start real `dsh web`; use browser automation to verify composer and `/model` searches by name, provider, and raw ID, selection, reasoning effort, reopen-reset, and official no-plugin fallback.
- Create public GitHub repo, push `main`, tag `v0.1.0`, create GitHub Release with tarball and checksums.
- Record tag, commit, asset URL, and SHA-256 for the Desktop lock.

