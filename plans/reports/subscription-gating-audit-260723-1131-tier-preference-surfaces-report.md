# Subscription Gating Audit — tier / preference / surface matrix

Read-only audit, 260723. States: **(a)** `.free`, never purchased · **(b)** subscribed, capability preference OFF · **(c)** subscribed + ON (usage visibility).

Key architectural fact first: the codebase implements the **§5.3 contextual-upsell model** (everything visible, gate fires on the concrete create/approve action), NOT the "hide as if it never existed" model of intent (a). Every gate is additionally wrapped in `env.entitlements.purchasesEnabled` (`LooxMembership.launchEnabled = false` → production is fully ungated today; only beta/DEBUG sees gates). Tier and capability-preference are two fully independent axes that never consult each other.

## 1. Surface-by-surface gating table

| Surface | Location | Gated by | State (a) shows | State (b) shows |
|---|---|---|---|---|
| Profile row "Loox" (tier lockup) | `Vaultify/Features/Profile/ProfileScreen.swift:51-53` | nothing (always) | "Loox" row → hub | same |
| Profile row "Family" | `ProfileScreen.swift:58` | nothing | full Family screen | same |
| Loox hub: plan section | `Vaultify/Features/Profile/LooxHubScreen.swift:25,57-95` | `purchasesEnabled`; free vs paid branch | "Upgrade to Loox Max" row (beta only; dark in prod) | "Your plan" + "Manage plan" |
| Loox hub: member seal | `LooxHubScreen.swift:116-118` | `tier > .free` | hidden | shown |
| Loox hub: feature grid (6 tiles: Private Email, Share Links, Open on Computer, Profiles, Sharing, Watchtower) | `LooxHubScreen.swift:136-171` | **nothing** — no tier, no preference | all 6 tiles + live counts, all navigable | identical — tiles ignore the OFF preference |
| Loox hub: Approval Mode toggle | `LooxHubScreen.swift:238-254` | nothing (mirrors Settings flag) | shown | shown |
| Settings rows "Private Email" / "Share Links" ("Email riêng tư"/"Liên kết chia sẻ") | `Vaultify/Features/Settings/SettingsScreen.swift:147-150`, row builder `:21-36` | none (always); subtitle = `CapabilityStatusText.label` | shown | shown, subtitle **"Off"** (`CapabilityBannerView.swift:116`) — this is the one good (b) surface |
| Settings: NO rows for `.quickView` / `.shortLink` prefs | `SettingsScreen.swift:147-150` vs `CapabilityID.allCases` (`VaultifyCore/Models/Capability.swift:6-17`) | — | — | pref exists in `CapabilityStore` but has no UI to see or flip it |
| Item detail: share toolbar button + "Share this item" row | `Vaultify/Features/ItemDetail/ItemDetailScreen.swift:197-203, 613-628` | nothing (owned, non-trashed) | shown, flow completable | shown |
| Share chooser (Quick Link / Share with a Loox user) | `Vaultify/Features/Sharing/ShareAccessSheet.swift:462-481` | nothing — both rows always | both offered | both offered; Quick Link path dead-ends 1 tap later |
| Approval share creation | `ShareAccessSheet.swift:269-325`; `ShareSpaceSheet.swift` (no gate) | `ApprovalPrerequisites` (iCloud + notifications) only — **no seat gate** | free (0 seats) completes the full ceremony | works; silently sets `approvalModeEnabled = true` (`:313`) |
| Quick Link create | `Vaultify/Features/Sharing/QuickLinkView.swift:163-203` | capability availability (create section) + `purchasesEnabled && LooxGate.canCreateLink` (`:188-194`) | button live; paywall `.linkQuota` after 3 in 30d (beta) | `.disabledByUser` → disabled button + footnote "Share Links are turned off in Settings." (`:174-178, 219`) |
| Quick View entry "Open on Computer" (item-detail menu) | `ItemDetailScreen.swift:89-92, 208-216` | manifest exposure AND `availability(.quickView, .create) == .available` | shown when exposure allows | pref off → menu item **vanishes silently** (no Settings row exists to explain) |
| Quick View approve (Face ID button) | `Vaultify/Features/Sharing/QuickView/QuickViewApprovalSheet.swift:76-92` | `purchasesEnabled && LooxGate.canApproveQuickView` | paywall `.quickViewQuota` after 3/30d (beta) | reachable only if entry visible |
| Alias create (reusable / per-site) | `Vaultify/Features/Personas/PersonaAliasesScreen.swift:151-155, 173-175`; quota `guardQuota :121-129`; availability `guardEmail :241-245` | quota gate + availability guard | buttons live; paywall `.aliasLimit` at 2nd retained alias (beta) | **dead buttons** — banner renders nothing for `.disabledByUser` (`CapabilityBannerView.swift:52-53`), `guardEmail` silently `return`s |
| Alias "Tap to activate" (reserved row) | `PersonaAliasesScreen.swift:250, 258-260` → `RelayService` | breaker only (`RelayService.swift:277`) — preference NOT enforced | works | **still works with pref OFF** (service layer ignores preference) |
| Editor Private Email bubble + sheet create row | `Vaultify/Features/ItemEditor/ItemEditorScreen.swift:289-293, 303-324, 529-531` | `RelayFeature.activeAliasesEnabled` + `createAliasAvailable` | shown | create affordance hides cleanly (good); reuse suggestions still offered (local data, correct) |
| Persona create | `Vaultify/Features/Personas/PersonaSwitcherScreen.swift:62-70` | `purchasesEnabled && LooxGate.canCreatePersona` | paywall `.personaLimit` at 2nd persona (beta) | n/a (no preference axis) |
| Watchtower paid rows (Full report, Fix Queue, History) | `Vaultify/Features/Watchtower/WatchtowerScreen.swift:221-241` | `purchasesEnabled && !LooxGate.fullWatchtower(tier)` on TAP | rows visible; tap → paywall `.watchtower` (beta). Free floor (score, audit, Critical/High groups) open | n/a |
| Themes / accents | `AppearanceSettingsView.swift` — no gate | `LooxGate.fullThemes` has **zero call sites** | all 7 accents free | n/a |
| Notifications inbox | `Vaultify/Features/Sharing/NotificationsScreen.swift:31-98` | nothing; feeding coordinators guard on `approvalModeEnabled` (`InviteInboxCoordinator.swift:36`, `ApprovalCoordinator.swift:116,201`) | shown | Approval Mode off → silently empty/stale, no "off" explanation |
| Paywall / plan screens | `LooxPaywallScreen.swift:45-63` (branches on tier), `LooxAcquisitionPaywallView`, `LooxPlanLandingScreen` (only reachable from paywall `:119`) | presented only from gate sites / hub, all `purchasesEnabled`-wrapped | acquisition layout | `LooxCurrentPlanView` |

### Deliberate acquisition / paywall entry points (state (a) — keep-or-hide decision list)
1. Profile → Loox hub "Upgrade to Loox Max" row (`LooxHubScreen.swift:60-71`) — the §5.3 Profile discovery point.
2. Contextual over-quota gates: persona create, alias create, link create, quick-view approve (4 sites above) — free tiers legitimately include small quotas (1 persona / 1 alias / 3 links / 3 quick views per 30d), so these surfaces are free features with a ceiling, not paid-only surfaces.
3. Watchtower paid-row taps (`WatchtowerScreen.swift:226-231`).
4. Paywall "Learn more" → `LooxPlanLandingScreen`.

### Violations ranked by visibility

**Intent (a) — free user:**
1. **HIGH — Approval-Mode sharing has no seat gate anywhere.** Free quota `outgoingRecipients: 0` (`LooxTier.swift:35`), but `LooxGate.canAddOutgoingRecipient` is **never called** (grep: zero call sites) — not in `ShareAccessSheet.createShare` (`:269-325`), not in `ShareSpaceSheet`, not in resume. `LooxPaywallContext.recipientLimit` (`LooxPaywallScreen.swift:14`) is dead code. A free user completes the entire share ceremony. Most-used share entry (item-detail toolbar) so highest visibility.
2. **HIGH — Loox hub feature grid ignores tier**: all six service tiles with counts and navigation render for free users (`LooxHubScreen.swift:136-171`). Under the §5.3 model this is the deliberate free hub — but it directly contradicts intent (a); decide explicitly.
3. **MED — Family surface ungated**: Profile → Family with "Share a Space" CTA (`FamilyScreen.swift:55-64`) for a tier with 0 seats.
4. **MED — `fullThemes` never wired**: gate + `.themes` paywall context dead; all accents free.
5. **LOW — Watchtower/persona/alias/link/quick-view visibility**: §5.3-by-design (see decision list).

**Intent (b) — subscribed, toggle OFF:**
1. **HIGH — PersonaAliasesScreen dead buttons.** Pref off → `.disabledByUser` → `CapabilityBannerView` deliberately renders nil (`CapabilityBannerView.swift:52-53` "user-off is a Settings state, not a banner"), yet both create buttons stay visible and `guardEmail` silently returns (`PersonaAliasesScreen.swift:242`). Tap → nothing. No text anywhere on screen.
2. **MED — Loox hub tiles ignore preference**: "Private Email"/"Share Links" tiles still show counts and navigate into screens whose primary action is off; the tile metric never says "Off" (`LooxHubScreen.swift:143-155`).
3. **MED — preference not enforced below the UI**: `RelayService` gates only on the breaker (`RelayService.swift:277`); alias-row "Tap to activate" performs live relay activation with the pref off. Same pattern in `LooxLinkService.createLink` (no preference check) — only the UI layer gates.
4. **MED — Notifications inbox goes silently dead** when Approval Mode is off (coordinators guard, screen doesn't explain).
5. **LOW-MED — Share chooser dead-end**: chooser always offers Quick Link (`ShareAccessSheet.swift:462-469`); with pref off the user reaches a disabled Create + "turned off in Settings" footnote two taps deep (`QuickLinkView.swift:219`). At least labeled, and the Settings row subtitle reads "Off" — intent (b)'s "one clear place" partially satisfied.
6. **LOW — `.quickView`/`.shortLink` prefs have no Settings row**: if ever false, Quick View entry vanishes with no re-enable surface (`SettingsScreen.swift:147-150` builds rows only for privateEmail/shareLink).

## 2. LooxGate — enforcement & counting

Pure upsell gates; **no counters live in LooxGate** — callers supply device-local counts. Over-even-Max deliberately returns `.allowed` (defers to future backend; `LooxGate.swift:58-70`). All at `VaultifyCore/Subscription/LooxGate.swift`:

```swift
enum Allowance: Equatable, Sendable { case allowed; case needsUpgrade(to: LooxTier) }
static func canCreatePersona(tier: LooxTier, current: Int) -> Allowance            // :22
static func canCreateAlias(tier: LooxTier, retained: Int) -> Allowance             // :27
static func canCreateLink(tier: LooxTier, createdIn30d: Int) -> Allowance          // :32
static func canApproveQuickView(tier: LooxTier, approvedIn30d: Int) -> Allowance   // :37
static func canAddOutgoingRecipient(tier: LooxTier, activeRecipients: Int) -> Allowance // :44 (UNUSED)
static func fullWatchtower(_ tier: LooxTier) -> Bool                               // :51
static func fullThemes(_ tier: LooxTier) -> Bool                                   // :54 (UNUSED)
```

Tier source: `LooxEntitlementStore` (`Vaultify/Services/Subscription/LooxEntitlementStore.swift`) — `var tier: LooxTier` (`:34-39`, DEBUG override `:77`), `var purchasesEnabled: Bool` (`:47-53`). Quota denominators: `LooxTier.quotas -> LooxQuotas` (`LooxTier.swift:30-50`).

### Locally available usage counts (for a "used X of Y" UI)

| Quota | Count expression (all already used by `LooxHubScreen.swift:174-197`) | Store / signature |
|---|---|---|
| Retained aliases | `env.repository.aliases.filter { $0.status == .active \|\| $0.status == .paused }.count` | `VaultRepository.aliases: [EmailAlias]` (`VaultRepository.swift:22`) |
| Personas | `env.repository.personas.count` | `VaultRepository.personas: [Persona]` (`:21`) |
| Link creates 30d | `env.looxLinks.records.records.filter { $0.createdAt >= cutoff }.count` | `LooxLinkRecordStore.records: [LooxLinkRecord]` (`LooxLinkRecordStore.swift:61`; record has `createdAt`) via `LooxLinkService.records` (`LooxLinkService.swift:10`) |
| Quick View approvals 30d | `env.quickViewHistory.rows.filter { $0.result == .completed && $0.timestamp >= cutoff }.count` | `QuickViewHistoryStore.rows: [QuickViewHistoryRow]` (`QuickViewHistoryStore.swift:32`; `rows(forItem:)`, `record(itemID:result:at:)`) |
| Active outgoing recipients | `Set(env.sharingStore.shares.filter { $0.status == .active }.map(\.recipientLabel)).count` | `SharingStore.shares: [ItemShareRecord]` (`SharingStore.swift:90`; `shares(forItem:)` `:102`, `shares(forRecipient:)` `:109`) |
| Watchtower / themes | boolean from `tier.quotas` | — |

Caveats: all device-local approximations (comments pin "backend counter is the enforcement authority once it exists"); the 30-day cutoff is **duplicated at three sites** (`LooxHubScreen.swift:176`, `QuickLinkView.swift:207-210`, `QuickViewApprovalSheet.swift:25-28`) with no shared helper; the hub's quick-view metric counts **completions** while the gate name says approvals (same store row, consistent in practice). Quota denominators render only when `showsQuotas` (`LooxHubScreen.swift:204-211`: `purchasesEnabled`, or DEBUG tier override).

## 3. "Bought but disabled" confusion flows

1. Paying user, Private Email off → PersonaAliasesScreen create buttons do nothing (no banner, no toast) — worst case; looks broken.
2. Paying user, Private Email off → alias row "Tap to activate" still hits the relay and works — feature is simultaneously "off" and working, undermining the toggle's meaning.
3. Paying user, Share Links off → item detail Share → chooser still offers "Quick Link" → disabled button + footnote; functional but a two-tap dead-end.
4. Paying user, Approval Mode off → Notifications screen silently empty/stale (coordinators guarded); no "Approval Mode is off" note, no Settings link.
5. Paying user, Approval Mode off → starting any new share silently flips `approvalModeEnabled = true` (`ShareAccessSheet.swift:313`, `ShareSpaceSheet.swift:277`) — re-enable-on-use is reasonable but unannounced (Settings turn-OFF has a confirm dialog; turn-ON never mentions it).
6. Hub tiles (Private Email / Share Links) show normal usage counts while the pref is off — a paying user sees no hint the feature is disabled until deep in a screen.
7. No paywall can wrongly hit a paying user with a toggle off: LooxGate paths are quota-based, and dead/hidden buttons never reach them — confirmed by call-site inspection (all 5 sites check quota only).

## 4. Profile membership surface today (for the redesign)

- **Entry:** `ProfileScreen.swift:47-59` section-2 card: `LooxTierLabel` row (brand-mark tile; title is the live tier: "Loox" / "Loox+" / "Loox"+MAX badge) → pushes `LooxHubScreen`; below it the "Family" row.
- **`LooxHubScreen`** (iCloud+ idiom) composition, top-down:
  1. Header: `LooxTierLabel(tier:, badgeHeight: 26, brandWeight: .bold)` large title + member name in secondary (`memberName` resolution `:126-132` — identity "Full Name" else persona name); right: `LooxMemberSeal` (paid only) — circular stamp, top arc localized "Subscriber" uppercased, bottom arc "✦ LOOX MAX/PLUS ✦", brand symbol center, one-shot reveal animation (`LooxMemberSeal.swift`).
  2. Plan card (`purchasesEnabled` only): free = "Upgrade to Loox Max" chevron row; paid = "Your plan" + tier name, divider, "Manage plan" → `LooxPaywallScreen(.profile)` (subscriber branch `LooxCurrentPlanView`: "Your plan" + tier, "Current period ends {date}", "Change plan" → `SubscriptionStoreView`, "Manage subscription" → Apple sheet).
  3. "Included with Loox" 2-column `LazyVGrid` of `LooxFeatureTile` (`LooxFeatureTile.swift`: icon tile, 2-line title, one metric footnote line). Metric copy (`LooxHubScreen.swift:214-232`): "\(used) of \(cap) in use" / "\(used) in use" (no quotas pre-launch), "\(used) of \(cap) in 30 days", Watchtower "Full protection"/"Essentials".
  4. Approval Mode toggle card (confirm-on-off dialog).
- **Known wart for the redesign:** "Share Links" and "Open on Computer" tiles navigate to `NotificationsScreen` (`:147-155`), which shows share invites/approvals — not link records or quick-view history. Link records render only inside `QuickLinkView`'s per-item "Active links" section.
- No service-status line exists on the hub today; capability availability (`CapabilityStatusText`) is surfaced only in Settings rows. `LooxMaxBadgeView`/`LooxTierLabel`/`LooxMaxTint`/`LooxPlanTint` (`LooxMaxBadgeView.swift`) are the reusable tier-identity components.

## 5. Test-frozen constraints (don't fight these)

- **`LooxTierTests`** (`VaultifyTests/LooxTierTests.swift`): tier ordering, brand display names, the **entire quota table** per tier, product-ID allowlist + max-first catalog order, `resolveTier` highest-wins. Header: changes = grandfathering/owner decision, not test edits.
- **`LooxGateTests`**: every gate boundary, including `canAddOutgoingRecipient(tier: .free, activeRecipients: 0) == .needsUpgrade(to: .plus)` (`:54`) — the free-0-seats contract already exists and expects to be CALLED; wiring the missing share gate is aligned with the tests. Also pins over-Max `.allowed` deferral and `fullThemes` true for plus/max.
- **`LooxSubscriptionStateTests`**: Apple-state → behavior mapping (grace = full access, billing-retry/refund = block new premium only, expired = free, undetermined = keep last verified).
- **`LooxEntitlementContractTests`**: backend binding-hash vectors + attach wire shapes (contract-frozen; irrelevant to UI changes but do not touch `LooxBindingHash`).
- **`CapabilityTests`**: `.read` never gated in ANY state (`testReadIsNeverGated` — local records must stay visible; don't "hide" alias/link lists under pref-off); `.disabledByUser` must stay a **distinct** availability case (`testDistinctStatesNeverCollapse:54`); operation table backend parity; breaker timings; `testCapabilitiesFailIndependentlyAndPreferenceIsUntouched` — outages must never flip the user preference (INV-CAP-09). A redesign may render `.disabledByUser` differently, but the resolver's case split is pinned.
- **`CapabilityManifestTests`**: quick-view exposure comes only from verified schema-2 manifests, fail-safe `.hidden`; unknown message keys never render raw. Any new "feature off" copy must go through the same whitelist pattern.
- Not test-frozen (safe to change): `CapabilityBannerView` rendering nothing for `.disabledByUser`, hub tile composition/destinations, Settings row set, the absence of the recipient-seat gate call.

---
Status: DONE
Summary: Full gating matrix produced: production is currently ungated (launch flag off); in gated builds the model is contextual upsell (§5.3), with two structural gaps — the outgoing-recipient seat gate and fullThemes are dead code — and the worst UX hole is Private-Email-off leaving dead create buttons with zero explanation. Usage counts for all five quotas are already computable from `VaultRepository`/`LooxLinkRecordStore`/`QuickViewHistoryStore`/`SharingStore` exactly as `LooxHubScreen` does today.
Concerns/Blockers: Intent (a) "disappear entirely" conflicts with the §5.3 contextual-paywall design pinned in code comments and the free tiers' nonzero quotas — an owner decision is needed before hiding surfaces; LooxGateTests already encode free = 0 sharing seats, so wiring the missing share gate is test-aligned.
