# dsh-preset-catalog Implementation Plan

> Execute with test-driven development. Every production behavior starts with a failing `node --test` case.

**Goal:** Publish an MIT-licensed DSH plugin that owns six searchable domain presets and installs/removes them safely through the official preset service.

**Repository:** `/Users/mars/Documents/小说/dsh-preset-catalog` -> `liusheldon238/dsh-preset-catalog`

**Release:** `v0.1.0`

## Task 1: Scaffold and catalog contract

Create `package.json`, `LICENSE`, `README.md`, `index.js`, `client.js`, `cordis.patch.yml`, `lib/catalog.js`, and `test/catalog.test.js`.

- Test first that the immutable catalog contains exactly the six approved IDs, localized names, categories, tags, searchable text, and no duplicate IDs.
- Implement only the metadata and pure case-insensitive substring/category filtering needed to pass.
- Commit: `feat: define domain preset catalog`.

## Task 2: Add validated preset assets

Create `presets/<id>/agent.cordis.yml`, `preset.yml`, `skills/<id>-workflow/SKILL.md`, `scripts/validate-presets.mjs`, and `test/presets.test.js`.

- Snapshot the supported DSH `0.1.1-rc.2` standard composition, applying only persona/skill guidance differences.
- Test first that every preset has safe IDs, valid YAML, required metadata, a readable skill, declared DSH compatibility, and only allowlisted baseline packages.
- Ensure skill locations are installed together with each preset and referenced through a stable absolute user-root path generated during installation rather than a build-machine path.
- Commit: `feat: add six validated preset bundles`.

## Task 3: Safe repository and HTTP boundary

Create `lib/repository.js`, `lib/routes.js`, `test/repository.test.js`, and `test/routes.test.js`.

- Test first: user root derivation, staging + validation + atomic rename, no overwrite, deterministic tree hash, modified-content removal refusal, cleanup after copy/validation failure, allowlist-only IDs, same-origin JSON POST, size limit, and mutation lock.
- Use `agentPresets.list()` as the installed/default source of truth; do not create a second database.
- Mount GET `list/status` and POST `install/remove` through `webServer.register()`.
- Commit: `feat: install preset bundles safely`.

## Task 4: Settings UI and graceful degradation

Create a plain client module and `test/client.test.js` using jsdom.

- Test first: localized catalog view, search across name/ID/category/tags/description, category filter, status badges, install/remove/default actions, modified-removal error, empty state, and missing-route no-throw fallback.
- Reuse `connection.api.settings.update({ ns: "agent-presets", patch: { default } })` for default selection.
- Root entry must not wait on optional services; use child `ctx.inject()` fibers so incompatible DSH leaves official UI intact.
- Commit: `feat: add searchable preset catalog UI`.

## Task 5: Integration, publication, and acceptance

- Run `npm ci`, `npm test`, preset validation, `npm pack --dry-run`, and install the tarball into a temporary DSH home.
- Start real `dsh web`, verify web boot, routes, install/list/default/remove, and browser UI.
- Create public GitHub repo, push `main`, tag `v0.1.0`, create GitHub Release with tarball and checksums.
- Record tag, commit, asset URL, and SHA-256 for the Desktop lock.

