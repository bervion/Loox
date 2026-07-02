---
phase: 3
title: "QuickType Passkey Identities"
status: completed
priority: P1
effort: "4h"
dependencies: [1, 2]
---

# Phase 3: QuickType Passkey Identities

## Overview
App-side publication: `ASPasskeyCredentialIdentity` entries join the system identity store on every unlock/reload so iOS proactively suggests Vaultify passkeys (F1). Extension-side append/removal already landed in Phase 2; this phase owns the app pipeline and serializes refresh against races.

## Requirements
- Functional: passkey identities published on unlock/reload, pruned on deletion, cleared on lock; refresh immune to stale-task overwrites.
- Non-functional: only non-secret metadata leaves the vault (`PasskeyInfo` — rpId, userName, credentialID, userHandle); private keys never enter the app-side cache (RT-11).

## Architecture
`VaultRepository` owns `passkeys: [PasskeyInfo]`, loaded in `reload()` through the injected `AppEnvironment.store` (Phase 1 — no per-call containers). `CredentialIdentityService.refresh(items:passkeys:)` publishes all three identity types using the shared identity factory (Phase 2). **Refresh is serialized** (RT-7): today each call spawns an unstructured fire-and-forget `Task` (`CredentialIdentityService.swift:23-32`) and reload fires on unlock, every scene activation (`RootView.swift:57-59`), and every CRUD — an older snapshot finishing last can resurrect a just-deleted passkey in QuickType. Fix: a tiny serialization point (actor or monotonically-increasing generation stamp) that drops stale snapshots before publishing.

## Related Code Files
- Modify: `Vaultify/Services/CredentialIdentityService.swift`
- Modify: `Vaultify/Data/Repositories/VaultRepository.swift`

## Implementation Steps
1. **VaultRepository**: `private(set) var passkeys: [PasskeyInfo] = []`; load in `reload()` via `PasskeyVault` `SecureBytes` overload (Phase 1 — session key used directly, no raw-array bridging); clear in `clear()`.
2. **CredentialIdentityService**: signature → `refresh(items: [VaultItem], passkeys: [PasskeyInfo])`; build passkey identities via the shared factory. Ordering: `replaceCredentialIdentities(passwordIdentities)` clears ALL types → then `saveCredentialIdentities(passkeyIdentities + otpIdentities)` (passkey identities are iOS 17-safe; keep the OTP iOS 18 guard).
3. **Serialize refresh** (RT-7): generation counter — each `refresh` captures `generation += 1`; after every `await`, abort publishing if a newer generation exists. Same guard on `clear()` vs in-flight refresh.
4. **Lock path**: `clear()` keeps `removeAllCredentialIdentities()`; verify passkey identities disappear on lock.
5. **Reachability check**: with identities published, `prepareInterfaceToProvideCredential(for:)` passkey branch fires from QuickType — verify the `identity.credentialID` allowed-list path signs correctly end-to-end.
6. Manual verification: unlock app → webauthn.io shows Vaultify passkey suggestion on QuickType/sign-in sheet; delete flow (Phase 4) prunes; rapid unlock→delete→background sequences never resurrect a deleted suggestion (RT-7 scenario).

## Success Criteria
- [x] Stored passkeys appear as QuickType suggestions after unlock; gone after lock
- [x] Stale-snapshot refresh race demonstrably closed (rapid CRUD + activation storm leaves store consistent with final state)
- [x] No `privateKeyRaw` reachable from `VaultRepository`/UI layer (`PasskeyInfo` only)
- [x] `make check` green (both targets)

## Validation
- 2026-07-02: `make check` passed; full `VaultifyTests` passed (101 tests). Manual QuickType sheet QA still planned before TestFlight.

## Risk Assessment
- **Identity-store enablement**: no-op unless Vaultify AutoFill is enabled (existing `state().isEnabled` guard) — keep.
- **Refresh latency**: serialization adds ordering, not blocking UX (publication is background).
- **Privacy**: userName/rpId enter the system index — same trust level as existing password identities; comment in code.
