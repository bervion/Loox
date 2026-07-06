# P2.2 — In-app isolation consumption: search gate + create-login suggestion

## Context links
- Canonical: `proposal-v3-locked-decisions.md` — **INV-R03**, **D6** (scoped search). Overview: `p2-plan.md`.
- Consumes engine from P2.1. Seams left by P1: `allSpacesSearchAllowed` (`VaultRepository+Folders.swift:278`),
  `activePersona` (`VaultRepository+Personas.swift:52`), `Persona.primaryProfileItemID`/`primarySpaceID`.

## Overview
- **Priority:** P2 · **Status:** pending · **Depends on:** P2.1
- The IN-APP half of INV-R03: drive search widening from policy, fix the `seedScope` `.allSpaces` leak,
  add a persona-scoped username-suggestion affordance to the create-login editor (greenfield — no prefill exists today).

## Key insights (verified)
- `allSpacesSearchAllowed` is consumed at `SearchScreen.swift:59` (offers `.allSpaces` chip) and `:134`
  (empty-state "Search all Spaces" escape hatch). Driving it false removes BOTH — good.
- **Leak path:** `seedScope()` (`SearchScreen.swift:97-101`) sets `scope = .allSpaces` whenever there is no
  `currentSpaceId`. Under strictAnonymous the chip is gone but the *seeded* scope still runs
  `repository.search(_, .allSpaces)` (`:73`) → cross-persona results. MUST be centralized + fail-closed.
- `.sharedWithMe` (`SearchScreen.swift:52-60`) surfaces cross-persona shared items → suppress under strictAnonymous.
- In-app editor `.new(.login)` starts blank (`ItemEditorScreen.swift:30`) — adding a *tap-to-fill* suggestion
  is additive; do NOT auto-write it (avoids surprising the user + keeps strictAnonymous safe by default: empty).
- Items are NOT persona-partitioned in P1 (`FolderSecret.personaId` nil) → strictAnonymous "own data" ≈ items
  in the persona's `primarySpaceID`. Document this boundary; it is intentional (full partition is P3+).

## Requirements
- `allSpacesSearchAllowed` returns `false` when the active persona's policy is `strictAnonymous`, else `true`.
- A single resolver decides the default search scope; strictAnonymous never yields `.allSpaces`.
- `.sharedWithMe` scope hidden under strictAnonymous.
- `identityUsername(forPersona:)` resolver: own profile email/name; falls back to global default identity
  ONLY for non-strictAnonymous personas.
- Create-login editor shows ≤3 tapped suggestions from `PersonaUsernameSuggester`, scoped to active persona.

## Architecture / data flow
```
active persona.isolationPolicy
   ├─ VaultRepository+Folders.allSpacesSearchAllowed  → SearchScreen chips + escape hatch
   ├─ VaultRepository+PersonaContext.defaultSearchScope(currentSpaceId:) → SearchScreen.seedScope
   ├─ VaultRepository+PersonaContext.showsSharedScope(base:) → SearchScreen availableScopes
   └─ VaultRepository+PersonaContext.usernameSuggestions() ─(builds [UsernameCandidate])→ PersonaUsernameSuggester → editor chips
```
New file `VaultRepository+PersonaContext.swift` centralizes ALL P2 repository read-helpers:
```swift
extension VaultRepository {
    var activeIsolationPolicy: PersonaIsolationPolicy { activePersona?.isolationPolicy ?? .standard }

    /// email ?? name of the persona's own profile item; global default only when not strictAnonymous.
    func identityUsername(forPersona persona: Persona) -> String? { ... }   // INV-R03 #4

    /// Fail-closed default search scope. strictAnonymous → .thisSpace(primarySpaceID ?? "") (empty id ⇒
    /// no folder match ⇒ empty results, never global). Else currentSpaceId ?? .allSpaces.
    func defaultSearchScope(currentSpaceId: String?) -> SpaceScope { ... } // INV-R03 #2

    /// ≤3 suggestions for a new login under the active persona (uses PersonaUsernameSuggester).
    func usernameSuggestions() -> [String] { ... }                         // INV-R03 #5
}
```

## Related code files
- **Create:** `Vaultify/Data/Repositories/VaultRepository+PersonaContext.swift` (<160 LOC)
- **Modify:** `Vaultify/Data/Repositories/VaultRepository+Folders.swift` — `allSpacesSearchAllowed` (line 278) → policy-driven.
- **Modify:** `Vaultify/Features/Search/SearchScreen.swift` — `seedScope` (97-101) → `defaultSearchScope`; `showsSharedScope` (52-54) gate; keep `availableScopes` chip logic.
- **Modify:** `Vaultify/Features/ItemEditor/ItemEditorScreen.swift` — suggestion chips for `.new(.login)`/`.draft` login (tap sets the username field only).
- **Modify:** `Vaultify/Resources/Localizable.xcstrings` — suggestion label(s) EN+VI. (Serialize vs P2.3/P2.4.)
- **Create:** `VaultifyTests/PersonaIsolationTests.swift`
- **Read for pattern:** `VaultRepository+Identity.swift:14` (`defaultIdentity`), `VaultReader.swift:46-50` (email??name), `SpaceScope.swift`.

## Implementation steps
1. Create `+PersonaContext.swift` with the four helpers. `identityUsername`: `item(id: persona.primaryProfileItemID)` →
   shared `username(from:)` (email ?? name); if nil and policy ≠ strictAnonymous → `defaultIdentity` username; else nil.
2. `usernameSuggestions()`: build `[UsernameCandidate]` — active persona profile (sourcePersonaID = active), global
   default identity (sourcePersonaID = nil), recents (`recentlyUsed`) usernames tagged by their item's persona-if-known
   (else nil) — then call `PersonaUsernameSuggester.suggestions(policy: activeIsolationPolicy)`.
3. `+Folders.swift`: `var allSpacesSearchAllowed: Bool { activeIsolationPolicy != .strictAnonymous }`.
4. `SearchScreen.seedScope`: `scope = env.repository.defaultSearchScope(currentSpaceId: currentSpaceId)`.
   `showsSharedScope`: `&& activeIsolationPolicy != .strictAnonymous`.
5. `ItemEditorScreen`: for a new login, render a horizontal row of `usernameSuggestions()` chips above the
   username field; tapping sets the username field value. Hidden when empty (strictAnonymous w/ no own profile ⇒ empty).
6. Add EN+VI strings. `tuist generate --no-open`; `make check`.
7. Tests + run `-only-testing:VaultifyTests/PersonaIsolationTests`.

## Todo
- [ ] `+PersonaContext.swift` (4 helpers + `username(from:)`)
- [ ] `allSpacesSearchAllowed` policy-driven
- [ ] `seedScope` uses `defaultSearchScope`; sharedWithMe gated
- [ ] editor suggestion chips (tap-to-fill username)
- [ ] EN+VI strings
- [ ] `PersonaIsolationTests` green

## Success criteria (INV-R03 — concrete assertions)
- strictAnonymous persona ⇒ `allSpacesSearchAllowed == false`; `availableScopes` excludes `.allSpaces` AND `.sharedWithMe`.
- `defaultSearchScope` under strictAnonymous returns `.thisSpace(...)` (never `.allSpaces`); with no primary Space
  the produced scope yields **empty** results, never the global set (assert `search(...).isEmpty`).
- `identityUsername(forPersona:)` for a strictAnonymous persona with a foreign/global-only email pool returns nil
  (or its OWN profile email) — asserts it never equals persona B's / the default identity email.
- `usernameSuggestions()` under strictAnonymous excludes persona B + default-identity values entirely.
- standard persona unchanged: All Spaces chip present, default-identity fallback works.

## Risk assessment
- **High L × High I:** `seedScope` bypass (the subtle leak). Mitigation: centralize in `defaultSearchScope` + a test that
  strictAnonymous never produces `.allSpaces` and returns empty when no own Space.
- **Med:** recents candidates lack a reliable persona tag (items unpartitioned) → tag `nil`, which strictAnonymous
  excludes (safe/fail-closed); standard still shows them. Accept.
- **Low:** editor chip clutter. Mitigation: cap 3, hide when empty.

## Security
- Resolver reads only already-decrypted in-memory items; no new persistence. strictAnonymous path is fail-closed.

## Next steps
Unblocks P2.3 (extension mirror consumes `activeIsolationPolicy` + `primaryProfileItemID`) and P2.4
(management UI sets the policy these helpers read). Serialize `Localizable.xcstrings` edits with P2.3/P2.4.
</content>
