# Phase 04 — Tests (owner's 12 scenarios + parity)

Priority: P0 · Status: pending · Depends: Phases 01–03

## Owner-required scenarios
1. Fresh install, no cache → launch → GA appears after refresh.
2. Existing beta cache → foreground refresh → GA applies.
3. Never open PersonaAliasesScreen → Quick View still appears.
4. Offline launch → last-known-good cache works.
5. Missing cache + network failure → core vault unaffected.
6. Launch + foreground race → one network request per document (dedupe).
7. Refresh failure → verified cache preserved.
8. Manifest version rollback (strictly older) → rejected.
9. Same-version recovery (cache lost, version == highest) → re-accepted (Phase 02 fix).
10. TestFlight beta cohort vs App Store general cohort (exposure resolver matrix).
11. Reactive UI update after manifest apply (no screen reopen).
12. Cross-env high-water isolation (staging never bumps prod).

## Existing suites to extend
- `VaultifyTests/CapabilityManifestTests.swift` (verifier, rollback, exposure parse)
- `VaultifyTests/QuickViewKernelTests.swift` (resolver matrix)
- Parity vectors: `Fixtures/cap-manifest-vectors-v1.json` — re-verify unchanged after
  guard relaxation (`>=` must not alter transcript bytes; only the accept predicate).

## New
- `VaultifyTests/SignedControlPlaneRefresherTests.swift` — dedupe, freshness, independent
  failure, missing→immediate, race→single request.

## Run
`make test DEST='platform=iOS Simulator,id=<UDID>'` — full suite must stay green
(currently 409/409). Report exact pass count in the send-back.

## Todo
- [ ] Refresher unit tests (scenarios 5,6,7)
- [ ] Rollback/recovery tests (8,9,12)
- [ ] Resolver cohort tests (10) — extend existing
- [ ] UI reactive test (11)
- [ ] Full suite green

## Success
- All 12 scenarios covered; full suite green; parity vectors unchanged.
