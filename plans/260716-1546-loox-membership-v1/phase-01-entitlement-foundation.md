# Phase 1 — Entitlement foundation

**Goal:** tier becomes a real, observable, StoreKit-derived fact the whole app can read.
No UI beyond a DEBUG override picker.

**Context:** proposal §4 (product catalog), §7 (entitlement architecture), §8.1 (state
table). Repo has zero StoreKit today (verified 260716). `AppEnvironment`
(`Vaultify/App/AppEnvironment.swift`) is where app-wide stores live; flag pattern to
mirror: `VaultifyCore/Theme/WallpaperFeature.swift`.

## Files

### Create — `VaultifyCore/Subscription/LooxTier.swift` (nonisolated)
- `enum LooxTier: Int, Comparable, Sendable { case free, plus, max }`
- `displayName`: "Loox" / "Loox+" / "Loox Max" (owner naming 260716; UI-only —
  never parse it).
- `struct LooxQuotas` + `static func quotas(for tier:)` — frozen §3.1 table:

| field | free | plus | max |
|---|---|---|---|
| `personas` | 1 | 3 | nil (no product cap) |
| `retainedAliases` | 1 | 10 | 200 |
| `linkCreates30d` | 3 | 30 | 300 |
| `quickViewApprovals30d` | 3 | 30 | 300 |
| `outgoingRecipients` | 0 | 1 | 10 |
| `fullWatchtower` | false | true | true |
| `fullThemes` | false | true | true |

- `enum LooxProductID` — the four §4.2 IDs as `String` constants +
  `static func tier(for productID: String) -> LooxTier?` (allowlist mapping; unknown
  ID ⇒ nil, never a guess).

### Create — `VaultifyCore/Subscription/LooxMembership.swift`
- `static let purchasesEnabled = false` (flip when ASC products + paywall QA done).
- Doc comment: what the flag hides (paywall, upgrade CTAs, gate sheets) and what it
  never hides (hub screen itself, usage counts).

### Create — `Vaultify/Services/Subscription/LooxEntitlementStore.swift`
`@MainActor @Observable final class`:
- `private(set) var tier: LooxTier = .free`
- `start()`: reads verified `Transaction.currentEntitlements`, keeps a
  `Transaction.updates` listener for the process lifetime (§7.5). Highest-tier
  verified, non-revoked, unexpired subscription in the group wins.
- Only `VerificationResult.verified` counts. `finish()` transactions delivered via the
  updates stream after the tier is applied (SubscriptionStoreView purchases surface
  here too).
- Never downgrade on transient error: `currentEntitlements` is local; if a read throws,
  keep last known tier and retry (§7.5, §8.1 last row).
- `#if DEBUG` `debugTierOverride: LooxTier?` (UserDefaults-backed) — when set, `tier`
  returns it. Simulator/dev testing without ASC.
- NOT here in V1: `appAccountToken` (§7.3) and backend handoff (§7.4) — backend does
  not exist; leave a doc-comment pointing at the proposal so the seam is obvious.

### Modify — `Vaultify/App/AppEnvironment.swift`
- `let entitlements: LooxEntitlementStore`, constructed with the other stores;
  `start()` kicked from existing app-start path (match how other stores boot).

### Modify — `Vaultify/Features/Settings/` (DEBUG only)
- Tiny `#if DEBUG` row in the existing developer/diagnostics area (scout for current
  debug surface; if none, add to `AboutView` bottom under DEBUG): segmented
  Free/Plus/Max bound to `debugTierOverride`.

### Create — `Loox.storekit` (repo root or `Vaultify/Resources/`)
- StoreKit configuration: one group "Loox Membership", four products, §4.3 prices,
  7-day intro offer on Max Annual only (§6.1).
- Wire via Tuist: `Project.swift` scheme `runAction` `options` →
  `storeKitConfigurationPath` (ProjectDescription supports it). Debug scheme only.

## Tests (`VaultifyTests/LooxTierTests.swift`)
- Quota table pins (each tier, each field — the §3.1 contract).
- Product-ID → tier mapping incl. unknown-ID ⇒ nil.
- Tier comparability (`free < plus < max`).
- Highest-entitlement-wins selection logic (extract as pure
  `static func resolveTier(from: [String]) -> LooxTier` so it tests without StoreKit).

## Validation
- `tuist generate --no-open` + `make check`.
- Unit tests on booted sim.
- DEBUG override flips tier live (verify via phase-2 UI once it exists; until then a
  DEBUG file-based self-test per CLAUDE.md "Verifying runtime behavior" is fine).

## Risks / notes
- iOS API ceiling 17.3: `Transaction.currentEntitlements`, `Product.products`,
  `SubscriptionStoreView` are all iOS 17.0+ — safe. Do NOT use
  `Transaction.currentEntitlements(for:)` variants or StoreKit views newer than the
  stable-Xcode SDK without `#available` guards (CI trap, CLAUDE.md).
- Concurrency: project default actor isolation is MainActor; StoreKit async sequences
  consumed in `Task`s owned by the store. Keep `LooxTier`/`LooxQuotas` `nonisolated`
  (VaultifyCore convention) so the extension target compiles them too.
- Never name a bash path/log with the word "build" (hook).
