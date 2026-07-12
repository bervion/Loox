# Phase 06 — Recipient safety-code verification gate (replace silent auto-TOFU)

## Context links

- Audit §3-S1 (threat: attacker-published grant pinned before any human check), §5-R9
- Auto-pin site: `Vaultify/Services/Sharing/SharedItemsProjection.swift:175-179`
- Safety code (already computed, both sides derive the SAME code): recipient `SharedItemsProjection.safetyCode` (`SharedItemsProjection.swift:69-75`), owner ceremony `TrustFingerprint.code` (`ShareAccessSheet.swift:357-358`)
- Pin store: `ApprovalRecipientService.swift:141-161` (Keychain, per owner+zone)

## Overview

- **Priority:** P1 (security, user-locked decision: implement, not just document)
- **Status:** completed
- **Description:** Today B's device silently TOFU-pins whatever owner key first appears in the zone; only A compares the code. Add a recipient-side, default-on, one-time "compare the safety code" interstitial: before FIRST use of a share's content, B either confirms the codes match or explicitly skips. The crypto pin mechanics stay identical; what changes is that trust becomes an explicit human decision.

## Key insights

- Threat window: A's iCloud (or CloudKit) compromised between B's accept and B's first fetch → attacker's grant gets pinned; B then trusts spoofed content and sends attacker-verifiable requests. The pin already rejects later key CHANGES — the gate closes the first-sight gap.
- Keep pinning WHERE it is (projection refresh) — the pin is the crypto anchor that freezes the key the moment it is first seen; the gate governs USE, not pinning. Separating "pinned" from "verified" means a swapped key between fetches is still caught by the existing pin check (`ApprovalRecipientService.swift:196`), while the human check governs whether content is trusted.
- Low-friction contract (user decision "optional-but-default"): one interstitial per share, two exits — "The codes match" (confirmed) or "Use without verifying" (skipped, recorded, never re-nagged). Dismissing decides nothing and re-prompts on next first-use. An explicit skip is strictly better than today's silent default.
- Grandfathering: shares pinned before this feature have been in active use under the old model — backfill them as confirmed to avoid retro-nagging (they can still be checked manually via the existing safety-code row, `ItemDetailScreen.swift:496-501`).
- AutoFill hole: shared credentials flow to the extension via `SharedCredentialsCache` + `CredentialIdentityService` (`SharedItemsProjection.swift:86-92`). If unverified shares fed AutoFill, B could "use" content without ever seeing the gate — withhold unverified shares from the cache until confirmed or skipped.

## Requirements

**Functional**
1. Per-zone verification state alongside the pin: `pending` | `confirmed` | `skipped`, stored in Keychain next to the pinned key; cleared with the pin on `leave` (`ApprovalRecipientService.swift:166-169`) and vault erase.
2. New pins get `pending`; pins existing before the feature are backfilled `confirmed` (legacy) exactly once, BEFORE the pin loop runs for new zones.
3. Gate surfaces (recipient side) while state is `pending`:
   - Shared item detail: values/actions hidden behind the interstitial (present on reveal/copy attempt or on first open of the shared item).
   - `RequestCodeView` / askEachTime request entry: gated the same way.
   - AutoFill: items from `pending` zones excluded from `SharedCredentialsCache` + `CredentialIdentityService` registration.
4. Interstitial shows the safety code (`TrustFingerprint` format, monospaced `Font.vaultCode` + `.monospacedDigit()`), explains the one-time compare with the owner, primary "The codes match", quiet secondary "Use without verifying", plain dismiss = decide later.
5. State transitions are terminal: `confirmed`/`skipped` never re-prompt. (Re-verification on key change is impossible by construction — key changes are rejected by the pin, not re-pinned.)

**Non-functional**
- All strings EN + VI; no "!", "—", "·". Design for the longest VI label.
- Token-driven UI: `Space/Radius/Metric`, `.vaultType`, `.themedForeground`, `PolarisIcon`, 44pt targets, light/dark/Reduce Motion pass (design-dna-standard checklist).
- Fail-closed: absence of a marker on a NEW pin means `pending` (never default-trust).

## Architecture / data flow

```
Projection refresh (SharedItemsProjection.refresh:172-199)
  [once] backfill: every zone with pin && no marker → confirmed(legacy)
  first-sight pin (unchanged) + set marker → pending
  cacheEntry build: skip zones where marker == pending      (AutoFill withheld)
Item detail / request entry (marker == pending)
  → SafetyCodeVerifySheet
     "The codes match"      → marker = confirmed → reveal + next refresh feeds AutoFill
     "Use without verifying" → marker = skipped  → same, choice recorded
     dismiss                → still pending, re-prompts next time
```

State storage: `ApprovalRecipientService` static funcs mirroring the pin API — `ownerKeyVerification(zoneID:) -> OwnerKeyVerification?`, `setOwnerKeyVerification(_:zoneID:)`, cleared in `leave`/`clearPin` path. `OwnerKeyVerification: String enum` lives in `VaultifyCore` (pure, testable). Backfill one-shot guard: a UserDefaults flag (device-local bookkeeping, non-secret).

## Related code files

**Create**
- `VaultifyCore/Sharing/OwnerKeyVerification.swift` (~30 lines) — enum + transition rule (`canPrompt`, terminal states), pure for unit tests.
- `Vaultify/Features/Sharing/SafetyCodeVerifySheet.swift` (~150 lines) — interstitial UI.

**Modify**
- `Vaultify/Services/Sharing/ApprovalRecipientService.swift:141-169` — verification marker storage next to pin; clear in `leave`.
- `Vaultify/Services/Sharing/SharedItemsProjection.swift` — backfill pass + set `pending` at pin site (`:175-179`); expose `verification(forItem:)` lookup; exclude `pending` zones from cache entries (`:86-92` and the equivalent build inside `refresh`); mark-verified API that persists and re-feeds the cache.
- `Vaultify/Features/ItemDetail/ItemDetailScreen.swift` — gate shared-item value reveal; reuse the loaded `safetyCode` (`:23,282,496-501`); present `SafetyCodeVerifySheet`.
- `Vaultify/Features/Sharing/RequestCodeView.swift` — gate request initiation while `pending`.
- `Vaultify/Localizable.xcstrings` — new strings EN + VI.

## Implementation steps

1. `OwnerKeyVerification` enum in VaultifyCore (rawValue-backed for storage; doc comment states the trust model: pin freezes the key, this records the human decision).
2. `ApprovalRecipientService`: `verificationAccount(zoneID:)` (owner+zone, parallel to `pinAccount`, `:145-147`); get/set via `KeychainStore`; `leave` clears both (`:166-169`). Also clear wherever `clearPin` is invoked.
3. `SharedItemsProjection.refresh`: before the zone loop, one-shot backfill (UserDefaults flag): every `acceptedApprovalZones()` zone with `pinnedOwnerKey != nil` && marker nil → `confirmed`. At the pin site (`:177-179`) set marker `pending` immediately after `pinOwnerKey`. Ordering inside one function guarantees legacy zones are marked before any new pin lands.
4. Projection: include verification in the built `SharedOrigin`-adjacent state (simplest: expose `func verification(forItem id: String) -> OwnerKeyVerification` reading the marker via the item's zone). Exclude `pending` zones when building `cacheEntries` for `SharedCredentialsCache`/`CredentialIdentityService` — add a comment explaining WHY (content must not be usable through AutoFill before the one-time trust decision).
5. `SafetyCodeVerifySheet`: code display (grouped, `Font.vaultCode.monospacedDigit()`), explainer copy ("Ask the owner to open this item's sharing details and read their safety code. If both codes match, this share came from them."), primary button "The codes match" (themedProminent), secondary "Use without verifying" (quiet, with a one-line consequence note), dismiss = later. Callback persists the state and triggers a projection cache re-feed.
6. `ItemDetailScreen`: for a shared item with `pending` state, replace value rows' reveal/copy actions with a single "Verify this share" affordance presenting the sheet (values stay masked); after confirm/skip, normal behavior. Keep the existing optional safety-code row for `confirmed`/`skipped` states (manual re-check surface).
7. `RequestCodeView`: same gate before composing a request (a request leaks intent to the zone owner — must not fire pre-decision).
8. xcstrings EN + VI for all new strings; Polaris icon for the shield/verify glyph (existing set only).
9. Compile check + design-dna pass (light/dark, VI longest-label, Reduce Motion, hit targets).

## Todo list

- [x] OwnerKeyVerification enum (VaultifyCore)
- [x] Marker storage + leave/clear wiring (clearPin now clears the marker too; leave goes through clearPin)
- [x] Backfill + pending-at-pin in projection
- [x] AutoFill cache exclusion for pending zones (single `buildCacheEntries()` shared by refresh/leave/recordVerification)
- [x] SafetyCodeVerifySheet UI
- [x] ItemDetailScreen gate (verify card replaces the value section while pending; safety-code row hidden until decided)
- [x] RequestCodeView gate (independent send-path guard so a layout change can't reopen the hole)
- [x] xcstrings EN + VI (6 new strings; existing "The codes match" reused, stale marker dropped)
- [x] Compile + design-dna checklist pass (tokens/Polaris/44pt/localized copy; light+dark on-device pass in release QA)

## Success criteria

- Fresh share: B opens the item → interstitial appears BEFORE any value is revealed; the code shown equals the code on A's `TrustFingerprintView` for the same pairing.
- Confirm → values usable, AutoFill serves the credential after next refresh; relaunch → no re-prompt.
- Skip → same usability, marker records `skipped`; relaunch → no re-prompt.
- Dismiss → values still masked; next open re-prompts.
- Pre-existing active shares: zero new prompts after update (legacy backfill).
- Unit: enum transition rules; backfill decision logic (pure part).

## Risk assessment

| Risk | L×I | Mitigation |
|---|---|---|
| Friction: users spam "Use without verifying" | M×L | Acceptable by design — an explicit informed skip replaces a silent default; copy states the consequence in one line, no scare language. |
| AutoFill exclusion confuses users ("credential missing in QuickType") | M×M | Item remains visible in-app with the verify affordance; first in-app open resolves it. Note in release QA script. |
| Backfill runs before a legacy zone's pin exists locally (fresh reinstall: pins are Keychain, may survive reinstall while UserDefaults flag resets) | L×L | Harmless: surviving pin + reset flag → backfilled `confirmed` again (idempotent, same outcome). Fresh device with no pin → normal `pending` path. |
| Two gates (detail + request view) drift | L×M | Both call one shared `verification(forItem:)` + one sheet component — single source of truth. |
| Extension reads stale cache written before this change (contains now-pending zones) | L×L | Cache is rebuilt on every projection refresh; first app open post-update rewrites it. |

## Security considerations

- Pin-then-verify keeps first-sight key freezing (no widened race) while removing silent trust — addresses the audit's spoofed-content/response exposure.
- Marker in Keychain beside the pin: same protection class, same lifecycle; never synced.
- `skipped` is recorded, auditable in a future threat-model doc; A-side request verification (`ApprovalCoordinator.swift:86-94`) is untouched — owner secrets were never exposed by this threat and remain so.

## Next steps

Phase 7 tests. Follow-up (out of scope): a `docs/` threat-model note describing the two-sided ceremony and the recorded-skip model so audits stop re-flagging it.
