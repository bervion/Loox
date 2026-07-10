# Phase 4 — Search superpower (zero-state · operators · zoom transition)

**Tier:** T2+T3 · **Priority:** P2 · **Status:** pending · **Depends:** P0 (+P1 strings)
**Owns exclusively:** `SearchScreen.swift`, new `SearchZeroStateView.swift`, new `SearchOperators.swift`

NO AI, NO network — all local, on-device.

## Context
- Audit DNA #10. `SearchScreen.swift:80-85` (SearchResultsList) zero-state = dead `ContentUnavailableView`.
- Scope chips only render when query non-empty (`:106-121`). Token search is AND over `searchText` (`:65-76`).
- `recentlyUsed` helper from P0. `PasswordAudit.analyze` gives weak/reused (used in `HomeScreen.swift:59`).
- Zoom transition (`navigationTransition(.zoom)`) is iOS 18+ → guard, push fallback.

## Requirements
1. **Zero-state (empty query)** → replace dead view with:
   - **Recently used** rows (P0 `recentlyUsed`, tap → detail).
   - **Quick filter chips**: Codes / Passkeys / Cards / Weak — each seeds a scoped result set (no typing).
2. **Local operator search** (typed): recognize leading/standalone tokens, localized EN+VI keyword list:
   - `2fa` / `otp` → items with TOTP; `weak` → `PasswordAudit` weak; `reused` → reused; `passkey` → has passkey;
     category tokens (login/card/note/identity…). Operators compose with free-text AND. NO network, NO HIBP.
   - Keyword→predicate map in `SearchOperators.swift` (pure, testable, EN+VI synonyms).
3. **Zoom transition (T3)**: Search result row → detail uses `.navigationTransition(.zoom)` on iOS 18+,
   `#available` guard, plain push fallback on 17.6. Pair with `matchedTransitionSource` on the row.

## Data flow
```
query "" ─► SearchZeroStateView ─► [recentlyUsed rows] + [filter chips]
                                          │ chip tap
                                          ▼
                              SearchOperators.predicate(filter) ─► results
query "2fa gmail" ─► tokenizer ─► {operators, freeText} ─► SearchOperators + repository.search ─► results
row tap ─► (iOS18: zoom source) ─► ItemDetailScreen
```
- Operators are pure functions over `[VaultItem]` (+ `PasswordAudit` where needed). No persistence, no I/O.
- Existing scope/persona isolation (`seedScope` fail-closed, `showsSharedScope`) **unchanged**.

## Files
**Create:** `Vaultify/Features/Search/SearchZeroStateView.swift`, `Vaultify/Features/Search/SearchOperators.swift`
**Edit (exclusive):** `Vaultify/Features/Search/SearchScreen.swift`
**Append strings:** `Localizable.xcstrings` (chip labels, keyword hints, EN+VI) — coordinate w/ P1.
`tuist generate` after new files.

## Implementation steps
1. `SearchOperators`: enum of filters + `keywords(for:locale)` (EN+VI) + `matches(_:in:audit:)`. Pure.
2. `SearchZeroStateView`: recents list + chip row; callbacks to set query/filter in `SearchResultsList`.
3. Wire into `SearchResultsList.body` `trimmed.isEmpty` branch; thread active-filter state.
4. Extend `results` to fold operator predicates with existing token AND search (keep persona isolation).
5. Add iOS 18+ zoom on `VaultItemRowLink` + guard; verify 17.6 push fallback.
6. `make check`.

## Todo
- [ ] `SearchOperators` pure map (EN+VI keywords)
- [ ] `SearchZeroStateView` (recents + Codes/Passkeys/Cards/Weak chips)
- [ ] wire zero-state into empty-query branch
- [ ] operator + free-text composition (isolation preserved)
- [ ] zoom transition iOS18+ guard + push fallback
- [ ] strings EN+VI
- [ ] `make check`; Reduce Motion (zoom off) verified

## Success criteria
- Empty search shows recents + working filter chips, not a dead illustration.
- `2fa`, `weak`, `reused`, `passkey`, category tokens filter locally; composes with free text.
- Zoom on iOS 18+, clean push on 17.6; no runtime symbol errors on stable-Xcode build.
- strictAnonymous persona still fail-closed (no cross-persona leak via operators).

## Risks
| Risk | L×I | Mitigation |
|------|-----|-----------|
| Operators bypass persona/scope isolation | M×H | operators filter WITHIN scoped result set; reuse `seedScope`/repository search; test strictAnonymous |
| `PasswordAudit.analyze` cost per keystroke (weak/reused) | M×M | compute lazily/once per query; cache like Home's `watchtowerIssueCount` |
| VI keyword collisions with free-text | L×M | operators only on standalone tokens; ambiguous → treat as free text |
| Zoom API unavailable on CI stable Xcode | L×H | `#if compiler` + `#available` guard mirrors existing glass pattern |

## Rollback
Delete 2 new files, revert `SearchScreen.swift`. Zero-state falls back to prior `ContentUnavailableView`.

## Security
No network/AI. All filtering on decrypted-in-memory items already loaded. Isolation invariants preserved.

## Next
Disjoint from P2/P3/P5. Feeds P6.
