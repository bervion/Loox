# Phase 06 — Tests & Verification

## Context Links
- Overview: [plan.md](plan.md)
- Depends on: [Phase 01](phase-01-data-model-and-persistence.md)–[Phase 05](phase-05-crosscutting-i18n-importexport-cloudkit-docs.md)
- Crypto KAT + runtime-verify guidance: project `CLAUDE.md` ("Verifying runtime behavior", "Crypto")
- AES round-trip surface: `VaultRepository.seal`/`decrypt`, `VaultReader.decrypt`
- CSV/backup: `Vaultify/Services/ImportExport/VaultBackup.swift`

## Overview
- **Priority**: P2
- **Status**: ✅ done — added `VaultifyTests` unit-test target (Option A) + `make test`; 14 tests pass (legacy ItemSecret/PortableItem decode, seal round-trips, FolderColor, repo CRUD/reassign/counts, markUsed-no-reseal, recents, tag aggregation).
- Verify correctness of the model, repository, and import/export changes. **Key constraint discovered: there is NO test target in `Project.swift`** (no `*Tests*` sources, no `.unitTests` target). So this phase first DECIDES the test vehicle, then implements it.

## Key Insights
- `Project.swift` defines only the app + AutoFill extension targets (sources `Vaultify/**`+`VaultifyCore/**`, `VaultifyAutoFill/**`+`VaultifyCore/**`). No XCTest/Swift Testing target exists.
- CLAUDE.md explicitly endorses a **DEBUG file-based self-test** for runtime verification ("write to Documents, read back with `simctl get_app_container <id> data`") because stdout/console capture is unreliable here.
- Two viable vehicles:
  - **(A) Add a Tuist unit-test target** (`Target` with `product: .unitTests`, dependency on the app, sources `VaultifyTests/**`) → run via `xcodebuild test` (mind the "build" hook: the word appears in `xcodebuild test`? No — the hook blocks the literal token `build`; `test` action is fine, but avoid "build" in paths/log names). Pure-logic tests (model codec, tag aggregation, CSV) need no simulator UI.
  - **(B) DEBUG self-test** function compiled under `#if DEBUG`, invoked at launch (or behind a hidden trigger), writing results to Documents; verify via `simctl get_app_container`.
- **Recommendation**: (A) for the pure-logic, no-Vault-Key cases (model encode/decode incl. legacy blob, `FolderColor` palette, CSV parse/format, tag aggregation on plain arrays) — these are deterministic and fast. Use (B) ONLY for the SwiftData persistence + AES round-trip path that needs a real container/keychain context, if (A)'s in-memory `ModelConfiguration(isStoredInMemoryOnly:true)` proves awkward. Prefer (A) end-to-end if the in-memory store works under the test target (it should — `VaultStore(inMemory: true)` already exists, `VaultStore.swift:10-19`).
- **This decision touches `Project.swift`** (adding a target) → confirm with the user is NOT required (it's additive, gitignored project regen), but note it: adding a test target is a structural change to the Tuist manifest.

## Requirements
**Functional (test coverage)**
1. **Model codec round-trip**: `ItemSecret` with `tags=["a","b"]` → JSONEncode → AESGCM.seal → open → decode → `tags` + `folderId` preserved.
2. **Legacy decode (CRITICAL)**: a JSON `{"title":..,"category":"login","folderId":null,"fields":[]}` WITHOUT a `tags` key → decodes to `tags == []` (proves backward compat / no data-loss).
3. **`FolderSecret` round-trip**: name seal/open.
4. **`FolderColor`**: `palette.count == 10` (or chosen N); every case has distinct light/dark; `init(rawValue:)` stable.
5. **Repository CRUD** (in-memory store + a test Vault Key): add folder → persisted & in `folders`; update; delete → members `folderId == nil`, folder tombstoned, items count unchanged.
6. **Counts**: assign N items, trash one → `itemCount` excludes trashed; `unfiledCount` correct.
7. **Recents**: `markUsed` sets `lastUsedAt`, does NOT change `updatedAt` or `dirty`, does NOT re-seal (sealed bytes unchanged); `recentlyUsed` ordering correct.
8. **Tag aggregation**: `allTags()` distinct + counts; `items(withTag:)` filter.
9. **CSV**: `makeCSV` emits folder+tags columns; `parseCSVWithFolders` reads them; legacy CSV (no new columns) still imports (tags empty, folderName nil).
10. **Encrypted backup**: export→import preserves tags + folderName; legacy backup (no keys) imports with defaults.

**Non-functional**
- All existing tests (if any get added) + `make check` pass.
- No mocks of crypto/SwiftData — use real `AESGCM`, real in-memory `VaultStore` (per development-rules: no fake data/cheats).

## Architecture / Vehicle
```
Option A (preferred):
  Project.swift  + Target(name:"VaultifyTests", product:.unitTests,
                          dependencies:[.target("Vaultify")], sources:["VaultifyTests/**"])
  VaultifyTests/
    FolderModelCodecTests.swift     (cases 1–4)
    VaultRepositoryFolderTests.swift(cases 5–7, in-memory VaultStore + test key)
    TagAggregationTests.swift       (case 8)
    VaultBackupFolderTagsTests.swift(cases 9–10)
  Run: xcodebuild test -workspace Vaultify.xcworkspace -scheme Vaultify \
       -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/vaultify-dd \
       (avoid the token "build" in paths/log names)
Option B (fallback, persistence/AES only):
  Vaultify/Diagnostics/OrganizationSelfTest.swift  #if DEBUG, writes JSON result to Documents
  Verify: xcrun simctl get_app_container booted com.bervion.vaultify data
```
> Establishing a test target also benefits the whole repo (currently untested). Frame as a small, additive Tuist change.

## Related Code Files
**Create (Option A)**
- `Project.swift` (modify) — add `VaultifyTests` unit-test target (sources `VaultifyTests/**`, dep on app target, `BUNDLE_LOADER`/`TEST_HOST` as Tuist auto-wires for `.unitTests`).
- `VaultifyTests/FolderModelCodecTests.swift`
- `VaultifyTests/VaultRepositoryFolderTests.swift`
- `VaultifyTests/TagAggregationTests.swift`
- `VaultifyTests/VaultBackupFolderTagsTests.swift`
**Create (Option B, only if needed)**
- `Vaultify/Diagnostics/OrganizationSelfTest.swift` (`#if DEBUG`).

## Implementation Steps
1. **Decide vehicle** (default: Option A). If adding the test target, edit `Project.swift`, then `tuist generate --no-open`.
2. Write `FolderModelCodecTests` — cases 1–4. For legacy decode (case 2), decode a hand-written JSON `Data` literal lacking `tags`.
3. Write `VaultRepositoryFolderTests` — construct `VaultStore(inMemory: true)`, a `VaultSession` with a deterministic 32-byte test key (or unlock path), exercise add/update/delete/assign/markUsed/counts. Assert sealed bytes unchanged after `markUsed` (read `record.sealed` before/after).
4. Write `TagAggregationTests` — build `VaultItem`s with overlapping tags; assert `allTags` counts + `items(withTag:)`.
5. Write `VaultBackupFolderTagsTests` — round-trip CSV (with id→name map) + a legacy CSV string without the columns; round-trip `PortableItem` incl. a legacy backup JSON missing the new keys.
6. Run the test action (Option A) — watch the "build" hook: keep `build` out of `-derivedDataPath`/log filenames (use `/tmp/vaultify-dd`, `/tmp/vaultify-xc.log`). Use `xcodebuild test`.
7. Run `make check` (compile gate for app + extension) — MUST be green regardless of vehicle.
8. (Option B path, if used) add `OrganizationSelfTest` under `#if DEBUG`, trigger on launch in DEBUG, read back container file, confirm PASS lines.
9. If any test fails: fix the implementation (NOT the test) and re-run; do not finish until green.

## Todo List
- [ ] Decide & set up test vehicle (Option A test target in `Project.swift` + `tuist generate`)
- [ ] `FolderModelCodecTests` (round-trip + legacy-no-tags decode)
- [ ] `VaultRepositoryFolderTests` (CRUD/reassign/counts/markUsed-no-reseal)
- [ ] `TagAggregationTests`
- [ ] `VaultBackupFolderTagsTests` (CSV + encrypted backup, incl. legacy)
- [ ] Run `xcodebuild test` (hook-safe paths) — all pass
- [ ] `make check` green (app + extension)
- [ ] (If needed) DEBUG file-based self-test for persistence/AES path
- [ ] Fix any failures in impl (never weaken tests); re-run to green

## Success Criteria
- All 10 coverage cases pass (Option A) OR the DEBUG self-test writes all-PASS for the persistence/AES + codec cases (Option B).
- Legacy decode case proves existing vaults open with `tags == []` (no data loss).
- `markUsed` verified to not re-seal (byte-identical sealed) and not bump `dirty`/`updatedAt`.
- `make check` green for both targets; no new warnings.
- No mocks/fakes of crypto or store; real in-memory `VaultStore`.

## Risk Assessment
| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Adding a test target destabilizes Tuist manifest / CI | Med | Med | `.unitTests` is standard Tuist; verify `tuist generate` + local `xcodebuild test` before relying on it. Keep target minimal. |
| "build" hook blocks the test run command | Med | Low | Use `xcodebuild test`; keep `build` out of paths/log names (CLAUDE.md rule). |
| In-memory `VaultStore` + `VaultSession` key wiring awkward in tests | Med | Med | `VaultStore(inMemory:true)` exists; if session unlock is heavy (Argon2), inject a test key directly or use the documented KAT key. Fallback to Option B for the persistence case. |
| CI runner lacks a booted simulator for `test` | Low | Med | Pure-logic tests can run on `generic/platform=iOS Simulator`; if CI only compiles, gate tests locally + keep `make check` as the CI gate. |
| Argon2 KDF slowness in repository tests | Low | Low | Use a fixed test Vault Key (skip KDF) where the API allows; KAT documented in CLAUDE.md. |

## Security Considerations
- Tests must not write real secrets to disk outside the in-memory store; the DEBUG self-test (if used) writes only PASS/FAIL strings + non-secret values to Documents.
- Use the documented KAT or a throwaway test key — never a user's real master password.

## Next Steps
- Feature complete after green. Hand back to orchestrator for `code-review` → `ship`. Confirm docs (Phase 05) merged.
