# Sharing / Family / Pairing — UX refactor proposal

> Follow-up 2026-10-07: Member navigation và Family entry/detail polish tiếp tục ở [plan mới](../261007-1825-loox-member-and-private-email-ux-overhaul/plan.md). Current `FamilyScreen` vẫn derive people từ shares; “People model done” bên dưới không phải bằng chứng independent family roster đã tồn tại. Reuse sharing ceremonies, không mở lại transport/crypto trong UI scope.

- Status: **APPROVED 2026-07-27 — in progress on `refactor/sharing-family-ux`.**
- Created: 2026-07-27
- Base: `main` @ v1.41.1 (clean)
- Evidence: 12-agent audit of `Vaultify/Features/Sharing/**`, `Vaultify/Services/Sharing/**`,
  `VaultifyCore/Sharing/**`, `Vaultify/Features/Profile/FamilyScreen.swift`,
  `Vaultify/Features/Settings/PairDeviceSheet.swift`, `VaultifyAutoFill/**`, `Project.swift`.
  Every claim below carries a `file:line`.

---

## 1. Diagnosis — why the flow feels confusing

### 1.1 The root cause: there is no "family" in the code

`FamilyScreen` members are not a roster. They are a one-line projection of the outgoing
share registry:

```swift
// FamilyScreen.swift:19-23
Dictionary(grouping: env.sharingStore.shares, by: \.recipientLabel)
```

No membership entity exists anywhere in the repo. So:

- The user's mental model — *"join a family first, then you can share"* — is the **inverse**
  of the code. In code, **the invite IS what creates the relationship**; there is nothing to
  join.
- But the UI names the screen with a group noun ("Family"), offers **no way to add a person**
  (`FamilyScreen.swift:55-64` — the only action is "Share a Space"), and tells you to go
  elsewhere in its empty state.

Neither model is expressed. That mismatch is the source of most of the confusion, and it is
why the user intuited "family needs its own flow first" — that intuition is **correct**, and
adopting it also removes the biggest technical friction (see §2.1).

### 1.2 The double field-configuration is a state-persistence bug, not crypto

Verified by an adversarial pass that tried to prove the opposite.

- The capability map is `@State`, never persisted: `ShareAccessSheet.swift:43`.
- `ItemShareRecord` has no capabilities field: `ApprovalModels.swift:35-68`.
- `createShare()` **never reads capabilities** — it passes only email + zone name
  (`ShareAccessSheet.swift:285-286`). So collecting fields *before* the invite is pure UX
  ordering.
- On resume, `enter()` unconditionally lands on `.config` and re-seeds every field to `.none`
  (`ShareAccessSheet.swift:249-271`), and the CTA gate
  `.disabled(!recipientEmail.contains("@") || !hasGrantedCapability)`
  (`ShareAccessSheet.swift:607`) **forces** re-selection — you cannot tap through.
- Resume then re-runs the whole `createShare()` CloudKit ceremony and re-polls for a profile
  the refresher had already fetched (`OwnerShareRefresher.swift:98`).

What genuinely requires the recipient's key is only the **seal + sign**
(`ApprovalCrypto.swift:156`, `ApprovalCanonical.swift:169-179`) — which happens at the end.
Nothing forces the *selection* to be re-made.

**Security regression hiding in this bug:** `allowMultipleDevices` defaults to `true`
(`ShareAccessSheet.swift:46`). A share the owner deliberately configured as **single-device**
silently resumes as **multi-device**, with no warning. The resumed default is strictly more
permissive than the owner's stated intent.

### 1.3 The safety code is impossible to compare at the moment it is asked

This is the decisive finding, and it fully vindicates the complaint.

`TrustFingerprintView.swift:21` tells the owner to compare the code with "the one shown at
the bottom of the shared item on their device". But the recipient's code is derived from the
**grant**:

```swift
// SharedItemsProjection.swift:112-117 — needs grants[id]
// ApprovalRecipientService.swift:315 — throws .grantMissing when the zone has no grant
```

and the grant is published **only inside** `confirmFingerprintAndPublish`, i.e. **after the
owner taps Activate** (`ShareAccessSheet.swift:413-436`).

> At the moment the owner is asked to compare, the recipient has no code. The owner-side
> ceremony is unperformable by construction.

Then the **same value** is confirmed a second time on the recipient side
(`SafetyCodeVerifySheet.swift:35-45`). Neither decision is transmitted to the other party
(`ApprovalRecipientService.swift:236-257` — local Keychain marker only), so the pair provides
no joint attestation. It is the same check billed twice.

And there is **no copy, no share sheet, no selectable text** on any of the three places a code
is rendered (`TrustFingerprintView.swift:25-32`, `SafetyCodeVerifySheet.swift:77-80`,
`ItemDetailScreen.swift:601-616`) — so a 17-character code must be transcribed by hand or
photographed. For a Da Nang ↔ overseas pair that is exactly as absurd as reported.

**What the code actually buys, honestly stated.** The transport is already Apple-authenticated:
`share.publicPermission = .none` and the participant is added by iCloud account
(`ApprovalShareService.swift:84-92`), and acceptance cross-checks participant IDs
(`InviteLinkService.swift:144-158`). The only adversary the SAS excludes is **Apple/CloudKit
itself substituting a key**. That is a real E2EE property, but it is narrow — and the
automatic part (pin on first sight, **reject** on change:
`ApprovalRecipientService.swift:206-218`) is strictly stronger than a human comparison and
already costs nothing.

**But it cannot simply be deleted.** A second adversarial pass proved a concrete attack if the
recipient-side gate goes away with nothing in its place: the recipient is shown **no sender
identity anywhere** — the invite row is literally "Share invitation" + a timestamp
(`NotificationsScreen.swift:123-134`) — and an accepted share writes straight into
AutoFill/QuickType (`SharedItemsProjection.swift:338-341, 394-402`). Anyone who knows your
iCloud email can run the shipped owner flow and inject an attacker-authored "bank.com" login
into your autofill. The `pending` fail-closed gate is currently the only thing stopping that.

**Resolution (both passes converge here):** the fix is not "remove the gate", it is
**move the decision to the moment it is meaningful and give it real information**.
`CKShare.Metadata.ownerIdentity` is already fetched and thrown away
(`InviteLinkService.swift:148-153`). Surfacing it turns "an anonymous item appeared" into
"nguyen@example.com wants to share with you" — one tap, at accept time, with the identity
visible. That is both **less friction** and **more security** than today, because today the
universal-link accept path has **zero** confirmation (`VaultifyApp.swift:66-78`).

### 1.4 The passkey failure is a one-line build bug — and it is worse than reported

`VAULTIFY_ICLOUD` is defined **only** in the app target's settings block
(`Project.swift:166`). The `VaultifyAutoFill` target block (`Project.swift:223-234`) has no
`SWIFT_ACTIVE_COMPILATION_CONDITIONS` key, and the project base settings don't define it
either. `$(inherited)` on the app target inherits *from the project*, it does not propagate
down to the embedded appex.

`VaultifyCore/**` compiles into both targets, so **in the shipped extension binary**:

```swift
// PasskeyApprovalTransport.swift:39-40  → fires unconditionally
#if !VAULTIFY_ICLOUD
throw Failure.notConfigured

// SharedGrantLiveCheck.swift:32-33      → fires unconditionally
#if !VAULTIFY_ICLOUD
return .unavailable
```

`PasskeyCeremonyView.swift:216-219` catches the first in a generic `catch` and prints
*"Couldn't reach the owner right now."* / *"Hiện không liên lạc được với chủ sở hữu."* —
the reported error, verbatim. The owner is never contacted at all.

**Wider blast radius than the report:** the second guard means **every shared-item AutoFill
fails**, not just askEachTime passkeys. Any shared login tapped in AutoFill returns
*"Couldn't verify access right now."* (`AutoFillView.swift:272-283`).

The entitlement is already present (`VaultifyAutoFill.entitlements` carries CloudKit +
`iCloud.com.bervion.vaultify`) — only the Swift flag was missed. Verified by direct read.

Even once fixed, a real product constraint remains and is currently stated **nowhere in the
UI**: the ceremony needs the owner **unlocked and foregrounded**
(`ApprovalCeremonyService.swift:53-60`) and answering within **45 s**
(`SharedAccessTimingPolicy.swift:16`) while the request TTL is 120 s — and the owner's path
costs a cold launch plus **two** Face ID prompts (unlock, then `ApprovalRequestSheet.swift:134`).

### 1.5 Every share to a known person re-runs the entire ceremony

`ShareAccessSheet.createShare` dedupes only *within one item* and only *unconfirmed* shares
(`ShareAccessSheet.swift:282-284`). A confirmed member therefore gets a **brand-new zone** —
new CKShare, new accept, new profile publish, new safety code. The repo already knows this:

```
// SpaceShareZoneDedupe.swift:9-13
// two different items shared to the same recipient mint two different zones today.
```

A pure, unit-tested helper `SpaceShareZoneDedupe.existingZoneName(...)` already exists
(`SpaceShareZoneDedupe.swift:33-36`) and is already used by the Space flow
(`ShareSpaceSheet.swift:79-83`) — the single-item flow just never adopted it.

There is also **no recipient picker anywhere**: both entry points are free-text
(`ShareAccessSheet.swift:526`, `ShareSpaceSheet.swift:201`).

### 1.6 Family / recipient detail shows the wrong things

- **Per-person item list exists** (`FamilyScreen.swift:112-168`) but is a stale `let` snapshot
  (`:114`), has no empty state, no item-type icon, and every row — pending included — opens
  the management sheet instead of the resume stepper (`:141-142`), unlike `ItemDetailScreen`
  which routes correctly (`:661-663`).
- **The detail sheet never names the item.** `infoSection` renders Recipient / Status / Date
  only (`ShareRecipientDetailSheet.swift:77-99`); `item` is resolved at `:29` and used for the
  field rows but its title is never shown. Sheet title is the static "Share Details". So the
  field list is the *only* context — exactly the reported problem.
- **Wrong context for non-logins** — this is the deeper half of the report. The recipient
  projection hardcodes the category:

  ```swift
  // SharedItemsProjection.swift:468-473
  VaultItem(id: origin.itemID, category: .login, title: …)
  ```

  and unknown field metadata falls back to `.password` (`:437`). A shared Secure Note or SSH
  key arrives on the other device as a **fake login**. `ItemCategory` has 8 cases
  (`ItemCategory.swift:6-13`), each with its own avatar icon.
- **`Share a Space` silently drops every non-login item.** The safelist is
  `guard item.category == .login` (`SpaceShareSafelist.swift:41-48`); the UI surfaces this only
  as "Logins: 0 of 12" plus a dead button (`ShareSpaceSheet.swift:212-213, 239`).

### 1.7 Blocker found in passing: revoke deletes far more than it says

`ShareRecipientDetailSheet` revoke calls `revoke(zoneName:)` → `modifyRecordZones(deleting:)`
(`ApprovalShareService.swift:467-491`) and `store.remove(zoneName:)` whose own doc says
*"Remove EVERY item-share in this zone"* (`SharingStore.swift:168-171`). With
`FamilyShareTransport.perGrantEnabled = true` and Space fan-out putting N items in one zone,
**revoking one item revokes everything shared with that person** — while the dialog says only
"They can't request codes anymore." A per-grant revoke API already exists and is used by the
fan-out executor (`SpaceShareMembershipExecutor.swift:37, 191`).

### 1.8 The grey-centered-void pattern is systemic, and one cause is a token collision

The reported "Sẵn sàng chia sẻ" screen is `TrustFingerprintView.swift:14-42`: shield glyph, a
3-line `.callout` `.secondary` centered paragraph, code card, CTA — no card, no ScrollView, no
anchored CTA, wrapped only in `.padding(Space.gutter)`.

The shape repeats via `.frame(maxWidth: .infinity, maxHeight: .infinity)` across **~30 states
in 8 files**: `ShareAccessSheet` (5), `ShareSpaceSheet` (5), `ApprovalRequestSheet` (5),
`QuickViewApprovalSheet` (3), `PairDeviceSheet` (3), `QuickLinkView` (2), plus
`SafetyCodeVerifySheet` and `TrustFingerprintView`. Cause: there is **no shared
status/outcome component** in `Vaultify/DesignSystem/Components` — only `VaultInfoBanner`,
`VaultSheetScaffold`, `VaultStatusBadge` — so every state was hand-rolled.

**The "enabled but grey" buttons are not a state bug.** `ThemedTintedButtonStyle` fills with
`theme.accentSoft` (`ThemedButtonStyles.swift:60`), where
`accentSoft = blend(selection, accent, 0.15)` and `selection = blend(accent, white, 0.88)`.
For the graphite and mono accents — both neutral greys — that computes to ≈`#D1D1D3`, while
the **disabled** prominent fill is `#D1D1D6` (`ThemedButtonStyles.swift:18`). The tinted rank
carries no border and no elevation, so **an enabled secondary CTA is literally the disabled
swatch**. Verified by reading both files.

Three more independent causes of the same symptom:
- `onlineActionAppearance` dims a still-tappable control to `.opacity(0.5)`
  (`OnlineActionGate.swift:13-15`) — the OS's disabled signal, and a direct violation of the
  project's own opaque-disabled rule.
- App-wide `.tint(Color.primary)` (`VaultifyApp.swift:51`, `VaultRootEnvironment.swift:27`)
  strips the tappable signal from every default-styled Button.
- Several primaries carry **no button style at all** (`ShareRecipientDetailSheet.swift:106-115,
  136-142`; `QuickViewApprovalSheet.swift:94-100` — a destructive security abort).

### 1.9 Not a contributor: "Send to Browser"

Quick View is dark by default in every build including DEBUG — `currentExposure` returns
`manifestExposure ?? .hidden` (`QuickViewExposureProvider.swift:33-41`) and no manifest ships.
Ruled out as a source of the reported confusion. ~2,100 lines compiled but unreachable.

---

## 2. Proposal

### 2.1 The one structural change: split "connect to a person" from "share an item"

Adopt the user's intuition, because it also matches the crypto and deletes an entire class of
friction.

**Today** — one flow does both, so every share pays the connection cost:

```
pick item → configure fields → invite → [wait / leave] → they accept →
notification → resume → RE-CONFIGURE → wait again → safety code → activate
```

**Proposed** — two flows:

```
CONNECT (once per person)          SHARE (per item, after connecting)
invite → they accept  →  done      pick person → pick fields → Face ID → done
```

Why this is the high-leverage move: once the person is connected, their
`ParticipantProfile` already exists in the reused zone, so `fetchParticipantProfile`
**succeeds on the first poll tick** (`ShareAccessSheet.swift:362`, before any sleep). The
grant seals and publishes immediately. **No waiting screen, no notification, no resume, no
second pass — because the reason they exist is gone.** This removes the reported pain by
construction rather than by patching the resume path.

First-ever share to a new person still needs the round trip; that case is handled by 2.2.

Implementation is smaller than it sounds — no new transport, no new crypto:
- `Family` → **People** screen gains a real primary action "Invite someone", which runs
  `createShare` for a membership zone with **no grants yet**.
- Both config forms gain a member picker above the email field (same one-liner as
  `FamilyScreen.swift:20`), **filtered by active persona** (zone reuse is persona-scoped by
  design, `SpaceShareZoneDedupe.swift:16-24` — an unfiltered picker silently mints a new zone).
- `ShareAccessSheet.createShare` adopts the existing `SpaceShareZoneDedupe.existingZoneName`
  helper instead of its per-item lookup.
- Fix the case-desync first (`ShareAccessSheet.swift:320` writes normalized, `:452` writes
  raw) or the picker inherits duplicate members and a broken dedupe.

### 2.2 Persist the owner's intent; auto-publish on acceptance

- Add `capabilities` + `allowMultipleDevices` to `ItemShareRecord` (or a sibling draft store).
  Exposure is the same class as today — field IDs and enum modes next to the recipient email
  already in plaintext `UserDefaults`; **no field values, no key material**.
- On resume, seed from the record instead of resetting to `.none`. This alone kills the
  re-selection **and** closes the silent single-device → multi-device widening.
- Route a `.readyForCeremony` resume **straight to the confirm step**, not back through
  `.config` → `createShare()` → `.waiting` → re-poll.
- When the acceptance push arrives and the vault is unlocked, **publish automatically** with
  the frozen capabilities (queue to next unlock otherwise). Precedent already ships: the Space
  fan-out publishes machine-derived capability maps through the same
  `SharedGrantComposer.publish` with zero per-field owner pass
  (`SpaceShareMembershipExecutor.swift:54-58`).

### 2.3 One confirmation per side

**Owner.** Delete the unperformable comparison screen. Replace `TrustFingerprintView` with a
scope confirmation — *"Share `<item>` with `<person>`: these fields"* + Face ID. That tap is
the real authorization (it is already the publish trigger,
`ShareAccessSheet.swift:413-436`); we are removing a misleading instruction, not a check.

**Recipient.** Move the decision to accept time and give it information:
- Show `CKShare.Metadata.ownerIdentity` (already fetched, currently discarded,
  `InviteLinkService.swift:148-153`) on the invite row and the accept sheet.
- One prompt: *"Accept share from `<identity>`?"* — this also **closes today's hole** where a
  tapped universal link joins silently with no confirmation at all.
- Remove the later blocking `verifyPromptCard` + `SafetyCodeVerifySheet` wall.
- **Keep** the automatic pin-with-reject-on-change — the genuinely strong property.
- **Keep** an optional, non-blocking "Compare safety code" row on the person screen, **with a
  copy / share affordance** (missing today), for anyone who wants the anti-malicious-cloud
  property.

Net: owner 1 confirmation, recipient 1 confirmation. Facebook-friend-request shape, and
strictly better than today's security posture.

### 2.4 Passkey / TOTP

1. Add `"SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) VAULTIFY_ICLOUD"` to the
   `VaultifyAutoFill` target in `Project.swift`. One line; unblocks all shared AutoFill and
   askEachTime passkeys. Add a test asserting the flag so it cannot regress.
2. Give the owner an actionable notification (`UNNotificationAction`) that opens straight into
   the approval sheet — the 45 s budget currently has to absorb a cold launch plus two Face ID
   prompts.
3. Fix `ApprovalRequestSheet.finished()` (`:202-213`), which says "Code sent" after approving a
   **passkey**; `isPasskeyRequest` is already computed at `:26-28`.
4. Fix the owner push body: `alertLocalizationKey = "approval.push.body"` is TOTP-worded
   ("Someone is asking for a verification code") but the subscription covers passkey requests
   too (`ApprovalShareService.swift:114-121` vs `PasskeyApprovalTransport.swift:70`).
5. Make the extension's terminal states actionable — today they are bare red text with no
   retry and 5 distinct causes collapsed into one misleading sentence
   (`PasskeyCeremonyView.swift:208-219`).
6. Give the recipient's passkey section a real affordance; today it is a dead HStack with no
   tap target (`SharedItemPasskeysSection.swift:39-64`) while the TOTP twin gets a full
   `RequestCodeView`.
7. TOTP: keep the flow, fix the doubled "Request Again" (baked into the sentence *and* a
   button, `RequestCodeView.swift:200-210`) and route the AutoFill TOTP path through the same
   in-extension ceremony as passkeys instead of killing the fill session
   (`AutoFillView.swift:290-295`).

### 2.5 People screen and per-person detail

- Rename to a person noun; **one** name across Profile row and hub tile (today: "Family" vs
  "Sharing", same screen).
- Person detail = the **item list** (data already exists), each row with title + category
  avatar + real status; derive from the observed store, not a stale snapshot; add an empty
  state; route pending rows to the resume stepper.
- Share detail sheet must **name the item** (title + category avatar in the header).
- **Per-item revoke** via the existing per-grant API; keep zone delete only for "remove this
  person entirely", with honest copy.
- Category-correct recipient rendering: carry `category` in `SharedDisplayEnvelope` and stop
  hardcoding `.login` (`SharedItemsProjection.swift:468-473`).
- Category-correct capability vocabulary: a note body / SSH private key / card PAN must not
  present as a bare toggle labelled "Shared", and non-TOTP secrets currently get **no**
  irreversibility warning while TOTP and passkeys do.
- Surface *why* a Space share dropped items instead of showing "Logins 0 of 12" + a dead button.

### 2.6 UI sweep (repo-wide, as requested)

1. New `VaultStatusScreen` component — top-anchored, left-aligned, scrollable, CTA anchored via
   `.safeAreaInset(edge: .bottom)`, matching the pattern already established in commit
   `aa55895` (`Level2SettingsView.swift:87-99`, `CreateMasterPasswordView.swift:68-75`) and
   already documented as correct in `QuickLinkResultView.swift:29-31`.
2. Migrate the ~30 centered-void states in the 8 files listed in §1.8.
3. Fix `ThemedTintedButtonStyle`: enforce a contrast floor against the canvas and give the
   tinted rank a distinct affordance so it can never collapse onto the disabled swatch.
4. Replace `onlineActionAppearance`'s `.opacity(0.5)` with an explicit offline affordance.
5. Style the unstyled primaries and the unstyled destructive abort.
6. Anchor the `.config` CTA (today it scrolls with the keyboard as the last Form row).

### 2.7 Localization (project rule: a missing VI value is a bug)

Full list in the audit. Headlines: 3 `LocalizedStringResource` sites missing `.inAppLocalized`
(follow device language, not the in-app toggle); **18** sites rendering raw
`error.localizedDescription`; "verification code" translated two different ways in adjacent
branches of one switch (`ApprovalRequestSheet.swift:103` vs `:107`) against the project
glossary; "Extra Protection" abandoned for an invented term in `QuickLinkView.swift:109`; the
safety-code concept given **four** different user-facing names; missing plural variations
("1 items", "1 seconds"); and VI status labels up to 2.3× EN truncating in a single-line
`LabeledContent` next to an unbounded email (`ShareAccessSheet.swift:566-573`).
Zero violations of the "!" / "—" / "·" rules were found — but five semicolons are used as idea
separators.

---

## 3. Phases

| # | Phase | Scope | Status |
|---|---|---|---|
| 0 | **AutoFill build flag** | §2.4.1 + compile-time guard | ✅ done, compiles |
| 1 | **UI defect sweep** | §2.6 + `VaultStatusScreen` | ✅ done, compiles |
| 2 | **Persist intent, auto-publish** | §2.2 + single-device fix | ✅ done, compiles |
| 3 | **Ceremony reduction** | §2.3, identity at accept | ✅ done |
| 4 | **People model** | §2.1 + §2.5 + per-grant revoke | ✅ done |
| 5 | **Passkey/TOTP UX** | §2.4.2-7 | ✅ done |
| 6 | **Localization + copy** | §2.7 | ✅ done |

**Verification: `** TEST SUCCEEDED **` — 925 unit tests, 2 UI tests and the snapshot suite all
pass on iPhone 17 Pro; app + embedded extension compile clean.** A first run on iPhone 11 failed
one snapshot at `585x180` vs `390x120` — a 1.5x scale mismatch from checking an @3x reference on
an @2x device, not a regression; it passes on the matching simulator. Catalog: 1599 keys, zero
missing Vietnamese values.

### Landed so far

- **Phase 0.** `SWIFT_ACTIVE_COMPILATION_CONDITIONS: $(inherited) VAULTIFY_ICLOUD` added to the
  `VaultifyAutoFill` target in `Project.swift`, plus `VaultifyAutoFill/CloudKitCompileGuard.swift`
  — a `#error` that fails the build if the flag ever goes missing again. A unit test could not
  catch this (the test target has the flag); the guard can never regress silently.
- **Phase 1.** New `Vaultify/DesignSystem/Components/VaultStatusScreen.swift`: top-anchored,
  left-aligned, scrollable, CTA anchored via `.safeAreaInset(edge: .bottom)`. ~30 centered-void
  states migrated across `ShareSpaceSheet`, `ApprovalRequestSheet`, `QuickViewApprovalSheet`,
  `PairDeviceSheet`, `QuickLinkView`. `ThemedTintedButtonStyle` no longer paints enabled and
  disabled with the same fill, and gains a hairline so the tinted rank stays legible on the two
  neutral accents. `onlineActionAppearance` stops using `.opacity(0.5)` (the OS disabled signal)
  on controls that are enabled. Unstyled Form actions given real ranks.
- **Phase 2.** `plannedCapabilities` + `plannedAllowMultipleDevices` on `ItemShareRecord`;
  new `ShareActivationService` publishes the grant when the recipient's key lands, driven both
  in-sheet and off-sheet by `OwnerShareRefresher`, so the owner is never asked twice. Covered by
  `VaultifyTests/ShareScopePersistenceTests.swift` (legacy decode, scope round trip, the
  single-device widening regression, sibling-safe removal).
- **Phase 3 (owner half).** The unperformable comparison screen is deleted
  (`TrustFingerprintView.swift` removed; the `.fingerprint` step is gone from both
  `ShareAccessSheet` and `ShareSpaceSheet`). `TrustFingerprint.code` is retained — it still backs
  the optional recipient-side comparison.
- **Phase 4.** Family screen reworked: "Invite someone" primary, per-person subtitle that
  separates active from waiting, per-person item list derived live from the store (was a stale
  snapshot) with category avatars and correct pending/active routing, and an empty state.
  Recipient picker + persona-scoped zone reuse in `ShareAccessSheet` via the existing
  `SpaceShareZoneDedupe` helper. Share detail now names its item. **Revoke blocker fixed**: one
  item's revoke used `revoke(zoneName:)` (a zone delete) and took every other item shared with
  that person with it; it now uses the existing per-grant API and only tears the zone down when
  the last share in it goes. Hub tile renamed "Sharing" → "Family".

## 4. Acceptance criteria

- Owner shares an item to an **already-connected** person: no waiting screen, no notification,
  no resume — field selection happens once.
- Owner shares to a **new** person: configure once; after acceptance the grant publishes with
  **zero** further owner interaction, or one Face ID if the vault was locked.
- Single-device scope never widens to multi-device without an explicit owner change.
- Recipient sees **who** is sharing before accepting.
- Shared logins fill from AutoFill; askEachTime passkeys reach the owner's device.
- Revoking one item does not revoke the others shared with that person.
- No screen in `Vaultify/Features/**` renders its primary content as centered secondary text on
  the bare background; no enabled control renders in the disabled swatch.
- Every touched string has an EN + VI value; VI verified at 375 pt and at Dynamic Type XL.

## 5. Decisions (owner, 2026-07-27)

1. **Ceremony reduction — ACCEPTED as proposed (§2.3).** Drop the human safety-code comparison
   from the default path; keep automatic pin + reject-on-change; show the CloudKit identity at
   accept time; keep "Compare safety code" as an optional row with a copy affordance.
2. **Phase 4 — FULL scope.** People screen with "Invite someone", recipient picker, zone reuse,
   per-person item list, and per-item revoke (incl. the revoke blocker and the case-desync
   duplicate-member bug).
3. **Non-login sharing — IN SCOPE.** Carry `category` through to the recipient, stop hardcoding
   `.login`, category-correct field vocabulary, and an irreversibility warning for non-TOTP
   secrets.
4. **Quick View — leave dark, do not touch.** Ruled out as a contributor; code retained for a
   later manifest rollout.
5. **Naming — keep "Family / Gia đình"** (lowest-risk, reversible). Unify the hub tile from
   "Sharing / Chia sẻ" to the same name so one feature carries one name.
