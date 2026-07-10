# Phase 11 findings — Sharing: owner flow + approval + recipient

13 owned surfaces (11 numbered rows + `ApprovedCodeView`, `ShareMiniProgressBar` sub-views), all
walked per the adversarial protocol. Presentational-only per phase brief: no grant/verify/
publish/ceremony logic touched, only visual hierarchy, button rank/style, spacing, typography,
one raw font, one hit-target, one copy string. Compile green (app + embedded extension).

User priority driving this pass: button-wall audit (design-dna-standard.md, DNA #7 "Action
hierarchy — no button walls", added mid-sweep). Two sheets had 3 simultaneously-visible,
equal-weight buttons; fixed by ranking + toolbar-overflow demotion of the destructive/
low-frequency action, per file ownership below.

## Action census (every visible button per sheet state, rank, disposition)

### ShareAccessSheet — 9-step machine (`.choose/.quickLink/.checking/.blocked/.config/.creating/.waiting/.fingerprint/.publishing/.done/.failed`)

| Step | Before | Rank issue | After |
|---|---|---|---|
| `.choose` | 2 nav rows (Quick Link / Share with a Loox user) | none — mutually-exclusive path picker, not competing CTAs | unchanged (pass) |
| `.config` | 1 button (Create Share, prominent) | none | unchanged (pass) |
| `.waiting` (not accepted) | 3 buttons always visible: **Done** (prominent) + **Nudge via Messages**/**Share Invite Link** (default style) + **Check Now** (default style) | button wall — 3 equal-weight CTAs, "Done" outranked the actual next step | **Nudge via Messages / Share Invite Link** primary (prominent, the one useful next action) + **Done** quiet secondary (`.themedTinted`); **Check Now** demoted to a toolbar `•••` menu (`toolbarTrailing`, shown only in `.waiting`) |
| `.waiting` (accepted) | same 3 buttons, all still shown even though nudging no longer applies | same wall, plus a stale action (nudging an already-accepted recipient) | **Done** primary only; **Check Now** still reachable via the toolbar menu |
| `.fingerprint` | 1 button (Activate Sharing, prominent, in `TrustFingerprintView`) | none | unchanged (pass) |
| `.done` | 1 button (Done, prominent) | none | unchanged (pass) |
| `.blocked` | 1 button (Check Again, prominent) | none | unchanged (pass) |
| `.failed` | 1 button (Try Again, prominent) | none | unchanged (pass) |
| `.creating`/`.publishing`/`.checking` | 0 buttons (progress only) | none | unchanged (pass) |

### ApprovalRequestSheet — ceremony states (`.idle/.authenticating/.waitingForFreshWindow/.issuing/.finished/.failed`)

| State | Before | Rank issue | After |
|---|---|---|---|
| `.idle` (request details) | 2 buttons: **Approve with Face ID** (prominent) + **Reject** (default style, same full-width/height — no visual rank difference) | "two adjacent buttons never differ in size/style without a rank reason" — they didn't differ at all | Approve stays prominent; **Reject** → `.themedTinted` (quiet secondary, same tap height) |
| `.authenticating`/`.issuing` | 0 buttons (progress, sheet non-dismissible) | none | unchanged (pass) |
| `.waitingForFreshWindow` | 0 buttons (countdown) | none | unchanged (pass) |
| `.finished`/`.failed` | 1 button (Done/Close, prominent) | none | unchanged (pass) |

### ShareResumeStepperSheet — per `ShareLifecycle` status

| Status | Before | Rank issue | After |
|---|---|---|---|
| `.inviteSent` | 1 primary (Send Invite via Messages) + `secondaryRow` = 2 equal-size buttons side by side (**Check Now** + **Cancel Invite**, destructive) = 3 total | button wall; destructive action visually equal to a routine refresh | **Send Invite via Messages** primary; **Check Now** solo quiet secondary (`.themedTinted`, full-width); **Cancel Invite** moved to toolbar `•••` menu (destructive, still confirmed via the existing `confirmCancel` dialog) |
| `.readyForCeremony` | 1 primary (Continue to Activate) + same 2-button `secondaryRow` = 3 total | same wall | **Continue to Activate** primary; **Check Now** solo quiet secondary; **Cancel Invite** in toolbar menu |
| `.accepted` | 0 primary + same 2-button `secondaryRow` = 2 equal buttons, no clear top action | 2 equal-weight buttons for a state where the actual answer is "nothing to do but wait" | **Check Now** solo quiet secondary; **Cancel Invite** in toolbar menu |
| `.active` | 1 button (Done, prominent) | none | unchanged (pass) |

### TrustFingerprintView
1 button (Activate Sharing, prominent). Pass, no change.

### NotificationsScreen — `inviteRow`
2 buttons, **Not Now** (`.bordered`) + **Accept** (`.borderedProminent`) — already rank-differentiated by native SwiftUI style, appropriately sized for a compact list row (not a full-width CTA context where `.themedTinted`/`.themedProminent` apply). Pass, no change.

### ShareRecipientDetailSheet (Form)
Each action (Send Update Now / Apply Changes / Revoke Access) lives in its own Form section,
not stacked as competing peers on one screen state — matches the existing Settings-style pattern
elsewhere in the app. Pass, no change.

### RequestCodeView / ApprovedCodeView
Single ranked action per phase (`Request Code` → `Request Again` on any terminal state); the
"…" menu (Copy / Large Type) on the delivered code is a menu, not stacked buttons. Pass on
hierarchy; two other defects found here (font, hit-target — see table below).

### FieldCapabilityRow / PasskeyCapabilityRow / InviteInboxBehaviors / MessageComposeView / ShareInviteSentSheet / ShareStepperModel
No competing-button states (Menu/Toggle rows, native `.alert`, decorative progress bar,
representable). Pass, no change.

## Findings table

| Surface | Protocol Q(1-5) | Finding | Fix | Severity | Status |
|---|---|---|---|---|---|
| ShareAccessSheet `.waiting` | Q3 hierarchy | 3 always-visible equal-weight buttons (Done/Nudge/Check Now), Done outranking the real next step, Nudge shown even post-acceptance | Ranked primary+quiet-secondary per `accepted` state; Check Now demoted to a new toolbar `•••` menu scoped to `.waiting` | High | Fixed |
| ShareResumeStepperSheet (all 3 non-active statuses) | Q3 hierarchy | `secondaryRow` = 2 equal-size buttons (Check Now + destructive Cancel Invite) beside the primary = 3-button wall; destructive action had no visual demotion | Cancel Invite moved to a toolbar `•••` menu (confirmation dialog unchanged); Check Now is now the sole quiet (`.themedTinted`) secondary | High | Fixed |
| ApprovalRequestSheet `.idle` | Q3 hierarchy | Approve + Reject same size/style — no rank differentiation | Reject → `.themedTinted` | Medium | Fixed |
| RequestCodeView / `ApprovedCodeView` | Q4 typography | Delivered TOTP code rendered with raw `.font(.body.weight(.bold))` instead of the app's own codes-are-typographic-objects rule; own doc comment says "same interaction language as the app's own TOTP rows" but used a different font | `.font(.vaultCode(.title3, weight: .semibold))` + `.minimumScaleFactor(0.7)`, matching `TOTPCodeView` | Medium | Fixed |
| RequestCodeView / `ApprovedCodeView` | Q3 hit target | "…" copy/large-type menu trigger is a 30×30pt circle, below `Metric.hitMin` (44pt) — same defect already fixed in ItemDetail's identical `ic_menu_horizontal` pattern (phase 5) | Added the same invisible `.frame(width: Metric.hitMin, height: Metric.hitMin).contentShape(Rectangle())` padding, visual circle unchanged | Medium | Fixed |
| ShareAccessSheet `.waiting` (pollExhausted hint) | Q2 copy accuracy | Hint text said "tap Check Now" but that button no longer exists on the row after the hierarchy fix | Reworded to "check again from the menu above"; EN+VI added to `strings-manifest-phase-11.md` | Low | Fixed |
| RequestCodeView `HStack(spacing: 12)` | Q4 spacing | Raw numeric spacing instead of a `Space` token | `Space.s3` (=12, no visual change) | Low | Fixed |
| NotificationsScreen inviteRow | Q3 hierarchy | Uses native `.bordered`/`.borderedProminent` instead of the app's `.themedTinted`/`.themedProminent` | Reviewed — appropriately sized for a compact row (themed styles assume `frame(maxWidth: .infinity)` full-width CTAs); no equivalent compact themed style exists | Low | Deferred (see shared-component-requests.md) |
| All other owned surfaces (Field/PasskeyCapabilityRow, InviteInboxBehaviors, MessageComposeView, ShareInviteSentSheet, ShareStepperModel, ShareRecipientDetailSheet, TrustFingerprintView, remaining ShareAccessSheet/ApprovalRequestSheet/ShareResumeStepperSheet states) | Q1-5 | Reviewed, all pass (see action census above + grep results) | — | — | Pass |

## 6 audit greps (owned files only)

1. **SE-width / Dynamic Type** (`\.frame(width:`, `GeometryReader`, `minimumScaleFactor`, `lineLimit(1)`): only decorative fixed frames (8pt status dot, 72pt success circle, 26pt step bubble/countdown ring — none tappable, all pre-existing exempt patterns) + intentional `lineLimit(1)` on single-line labels/timestamps. `minimumScaleFactor(0.7)` newly added once (RequestCodeView code display), at the floor allowed by the standard. Clean.
2. **Typography** (`\.font(\.`): 1 raw hit found and fixed (`ApprovedCodeView`, see above); remaining hits are `.font(.vaultCode(...))`, the sanctioned API. Clean after fix.
3. **Radius** (`cornerRadius(` numeric / `RoundedRectangle(cornerRadius:`): zero hits — all owned surfaces already use `.vaultCornerRadius(Radius.md)` or the `RoundedRectangle(cornerRadius: Radius.md, style: .continuous)` token form. Clean.
4. **Spacing** (numeric `\.padding(`): zero hits (one numeric `HStack(spacing:)` outside the strict `.padding(` grep was still fixed, see findings). Clean.
5. **Hit target** (`\.frame(width:` on tappable glyphs): 1 hit found and fixed (RequestCodeView's 30pt menu trigger); all other fixed-size frames are decorative/non-tappable. Clean after fix.
6. **Haptics** (`Haptics\.`): zero call sites in these files — approve/reject/copy haptics fire from the ceremony service / `ClipboardService`, not the view layer, matching the vocabulary table exactly. Clean.

Color audit (raw `.white/.black/.gray/.red/.primary/.secondary`): only matches are
`.themedForeground(.secondary)` role arguments (sanctioned semantic API), zero raw `Color`/
`.foregroundStyle` literals. Clean.

Copy audit (`!`, `—`, `·` inside UI string literals, not code comments): zero hits in
user-facing strings (one `!= nil` false-positive inside a debug diagnostics log, not
user-facing). Clean.

## Shared-component requests
None filed — every fix used existing shared styles (`.themedProminent`/`.themedTinted`,
`VaultSheetScaffold`'s `trailing:` slot, the established `ic_menu_horizontal` padded-hit-target
pattern from phase 5). One deferred low finding (NotificationsScreen's native button styles)
noted in `reports/shared-component-requests.md` as a "would be nice" — not blocking, no compact
themed style currently exists and inventing one is out of scope for a presentational-only pass.

## Haptics verification
Ceremony/copy haptics are all service-owned (not view-owned) in this cluster:
`ClipboardService` fires the copy success haptic (`ApprovedCodeView.copy()` calls
`env.clipboard.copy(...)`, never a second haptic from the view); `ApprovalCeremonyService`
owns approve/reject/auth-fail haptics internally (untouched, presentational pass only touched
button style). No doubled haptics found.
