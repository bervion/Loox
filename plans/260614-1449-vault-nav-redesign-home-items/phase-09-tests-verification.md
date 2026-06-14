# Phase 09 — Tests + Verification

## Context Links
- Test target: `Project.swift:121-130` (`VaultifyTests`, `product: .unitTests`, sources `VaultifyTests/**`)
- Test pattern: `VaultifyTests/VaultRepositoryFolderTests.swift` (in-memory store + `adoptUnlocked`)
- Other suites: `VaultifyTests/VaultBackupFolderTagsTests.swift`, `OrganizationCodecTests.swift`
- Repo API under test (Phase 2): togglePin/archive/unarchive/markUsed-useCount + accessors + cache split
- Run: `make test DEST='platform=iOS Simulator,id=83B71AA8-A3FA-4095-9D05-226A6FE1FE75'` (scheme Vaultify)

## Overview
- **Priority:** P1
- **Status:** pending
- **Depends:** Phases 2–7 (API + UI landed).
- Add unit tests for the new repository behavior and verify the whole redesign builds + passes:
  `make check` (compile) + `make test` (14 existing + new, all green). Note the DEBUG runtime self-test.

## Key Insights
- **Test target EXISTS** (added with Spaces/Tags — verified `Project.swift:121`). Earlier project notes
  said "no test target"; that is now stale. Use the established pattern: `VaultStore(inMemory: true)` +
  `VaultSession` with `session.adoptUnlocked(key: [UInt8](repeating: 0x2a, count: 32))` + `repo.reload()`
  (verified `VaultRepositoryFolderTests.swift:9-15`). No Argon2/keychain needed → fast, deterministic.
- 14 tests currently pass; the Phase 2 change is additive (no API removed) → existing tests should stay
  green. The `testMarkUsedDoesNotReseal` test (`:43-55`) MUST still pass after adding `useCount += 1`
  (useCount is a column bump, still no re-seal / no updatedAt / no dirty — verify the assertions hold;
  useCount change does write the record via `save()` but the test asserts sealed/updatedAt/dirty
  unchanged, which remain true).
- New tests are pure repo-logic — ideal for the unit target. UI (tabs/Home/Items) is verified by build +
  manual/DEBUG self-test, not unit tests (SwiftUI view testing is out of scope, YAGNI).

## Requirements
**Functional (new tests):**
- `togglePin`: flips `pinned`; item appears in `repository.pinned`; no re-seal / no updatedAt bump.
- `archive`/`unarchive`: archived item leaves `items`, enters `archived`; unarchive reverses; no re-seal.
- `markUsed` increments `useCount` (and still no re-seal/updatedAt/dirty — extend existing assertion).
- `frequentlyUsed(limit:)`: sorts by `useCount` desc, respects limit, excludes zero-count appropriately.
- `recentlyCreated(limit:)`: sorts by `createdAt` desc, respects limit.
- `recentlyModified(limit:)`: sorts by `updatedAt` desc.
- Archived item excluded from `items`, `items(inFolder:)`, `items(withTag:)`, `allTags()`, counts.
- `item(id:)` (Phase 7) resolves a live AND an archived item.
- (Optional) `VaultRepository.search(_:)` token-AND incl. space-name match (Phase 3 logic).

**Non-functional:** all green; no fake data/mocks bypassing real store; deterministic.

## Architecture
- New test file(s) under `VaultifyTests/**` (picked up by the glob after `tuist generate`). Group by
  concern: a `VaultRepositoryPinArchiveTests` + extend recents/frequency coverage. Use the existing
  `makeRepo()` helper pattern (copy or share via a small test helper).

## Related Code Files
**Create:**
- `VaultifyTests/VaultRepositoryPinArchiveTests.swift` (≤170 LOC) — pin/archive/unarchive +
  archived-excluded-from-items + item(id:) lookup.
- `VaultifyTests/VaultRepositoryRecentsFrequencyTests.swift` (≤140 LOC) — useCount/frequentlyUsed/
  recentlyCreated/recentlyModified.
- (Optional) `VaultifyTests/VaultSearchTests.swift` — smart-search helper (if `search(_:)` added).

**Modify:**
- `VaultifyTests/VaultRepositoryFolderTests.swift` — extend `testMarkUsedDoesNotReseal` to also assert
  `after.useCount == before.useCount + 1` (or add a sibling test).

## Implementation Steps
1. Write `VaultRepositoryPinArchiveTests` (pin flips + in `pinned`; archive moves item→`archived`,
   out of `items`/counts/tags; unarchive reverses; `item(id:)` finds live + archived).
2. Write `VaultRepositoryRecentsFrequencyTests` (seed items, call markUsed N times, assert
   frequentlyUsed order/limit; assert recentlyCreated/recentlyModified order).
3. Extend the markUsed test for useCount.
4. (Optional) search test.
5. `tuist generate` (new test files) + `make check`.
6. `make test DEST='platform=iOS Simulator,id=83B71AA8-A3FA-4095-9D05-226A6FE1FE75'` → all green
   (14 existing + new).
7. DEBUG runtime self-test note: for persistence sanity (columns survive relaunch, migration on an
   existing vault), use the file-based self-test (write to Documents, read back via
   `xcrun simctl get_app_container <id> data`) — console capture is unreliable here.

## Todo List
- [ ] VaultRepositoryPinArchiveTests (pin/archive/unarchive + excluded + item(id:))
- [ ] VaultRepositoryRecentsFrequencyTests (useCount/frequentlyUsed/recentlyCreated/recentlyModified)
- [ ] Extend markUsed test for useCount
- [ ] (Optional) search test
- [ ] `tuist generate` + `make check` green
- [ ] `make test` all green (14 + new)
- [ ] DEBUG self-test for migration/persistence (note)

## Success Criteria
- `make check` green (app + extension).
- `make test` green: all 14 existing + every new test passes (no skipped/ignored failures).
- Archived-excluded and pin/frequency behaviors proven by tests, not just by reading code.

## Risk Assessment
| Risk | L×I | Mitigation |
|---|---|---|
| `testMarkUsedDoesNotReseal` breaks because useCount write changes the record | Med×Med | Test asserts sealed/updatedAt/dirty unchanged — all still true (column-only bump). Confirm assertions don't include "no save". Extend, don't fight it. |
| New test files not compiled (glob miss) | Low×Med | `tuist generate` after adding files; verify they appear in `make test` output. |
| Migration on existing on-disk vault untested by in-memory tests | Med×Med | In-memory tests cover logic; DEBUG file-based self-test covers on-disk migration/persistence. |
| Flaky ordering when createdAt/updatedAt collide | Low×Low | Seed with explicit, distinct dates in test fixtures. |

## Security Considerations
- Tests use a fixed dummy key (`0x2a`×32) on an in-memory store — no real secrets, no keychain. Mirrors
  existing suites. No security regression introduced by tests.

## Next Steps
Redesign complete. Commit on `feat/vault-spaces-tags` (PR #1). Consider `/ck:code-review` before merge.

---

## Open Questions (consolidated — for user)
1. **Home section order** — exact display order of the four default-ON sections? Assumed:
   Pinned → Favorite → Recently Created → Frequently Used. Confirm.
2. **Optional sections default** — Recently Used + Recently Modified default OFF (added via Customize)?
   And are the four default sections user-hideable, or always shown? (Phase 5 assumed all toggleable,
   4 on / 2 off.)
3. **Items → Categories visibility** — show ALL categories or only those with count > 0? (Assumed
   non-empty only, matching the old `HomeDashboard.visibleCategories`.)
4. **Search tab empty-state** — copy/illustration when query is empty (before typing)? Neutral
   placeholder assumed.
5. **Export & archived** — should Import/Export include archived items? Currently they'd be EXCLUDED
   (export reads `repository.items`). If archived must be backed up, export needs `items + archived`.
6. **Archive row actions** — does archiving offer move-to-trash too, or only unarchive? (Assumed
   unarchive primary; move-to-trash optional secondary.)
7. **Generator placement** — Utilities row label "Password Generator" and push vs sheet? (Assumed push.)
8. **Settings presentation** — gear opens Settings as a sheet (assumed, to avoid nested NavigationStack)
   vs pushed. Confirm.
