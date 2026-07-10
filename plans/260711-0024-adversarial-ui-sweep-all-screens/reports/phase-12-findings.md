# Phase 12 — Sharing: Quick Link + Quick View + Shared-with-Me: Findings

Scope: `Sharing/QuickLink*` (3 files), `Sharing/QuickView/*` (UI sheets only — 4 files reviewed,
`QuickViewScannerSheet` camera-exempt), `Sharing/SharedWithMeScreen.swift` (10 surfaces per phase
brief; 9 confirmed in the phase-00 registry). The ~17 crypto/API/model/attestation files under the
same directories (`LooxLink*` service/crypto/attestation, `QuickView*` API client/canonical/config/
envelope/exposure/history/human-code/payload/QR/SAS/session-envelope/field-kind/field-manifest) are
review-exempt and untouched. Method: `docs/design-dna-standard.md` adversarial protocol Q1-5 + the 6
audit greps + the mid-sweep "Action hierarchy — no button walls" addition. Protagonist: Quick Link =
"make an encrypted link anyone can open, safely, with limits"; Quick View = "hand one field to a
browser, once"; Shared-with-Me = "use what someone shared, read-only".

## User-named hot spot: QuickLinkResultView (post-create result)

**Before** (action census — one continuous button wall, 4 stacked full-width controls, no size/style
rank):

```
[✓ icon]  Link ready
[  shortened/full URL, mono, centered  ]
scope-warning line
one-time / expires line
┌─────────────────────────────┐
│  Copy Link          (filled) │  rank 1 (only correctly-styled one)
└─────────────────────────────┘
┌─────────────────────────────┐
│  Share Link      (unstyled)  │  rank ? — same width/height as primary,
└─────────────────────────────┘             no visual demotion
┌─────────────────────────────┐
│  Shorten Link    (unstyled)  │  rank ? — same width/height, conditional
└─────────────────────────────┘
short-link-unavailable line (conditional)
"revoked only from this device" line
┌─────────────────────────────┐
│  Done            (unstyled)  │  rank ? — same width/height
└─────────────────────────────┘
```
4 tappable rows, only 1 with an explicit `ButtonStyle` (`.themedProminent`); Share/Shorten/Done fell
through to SwiftUI's default automatic style in a non-List `VStack`, which renders as plain tinted
text at the SAME `controlMedium` width/height as the primary — so all 4 read as equal-weight, "which
one do I tap" (exactly the user's complaint: "quá nhiều button, style chưa hợp lý, sắp xếp, bố cục
chưa hợp lý").

**After** (primary + 1 quiet secondary + a small demoted-extras row, matches DNA rule 7 exactly):

```
[✓ icon]  Link ready
[  shortened/full URL, mono, centered  ]
scope-warning line
one-time / expires line
┌─────────────────────────────┐
│  Copy Link      (filled, controlLarge) │  PRIMARY — the one thing
└─────────────────────────────┘
┌─────────────────────────────┐
│  Done      (tinted, controlMedium)     │  SECONDARY — quiet, visibly smaller weight
└─────────────────────────────┘
   [↗ Share Link]      [✨ Shorten Link]      ← small icon-over-label chips,
                                                same shape as the system share
                                                sheet's own quick-action row;
                                                still ≥44pt each
short-link-unavailable line (conditional)
"revoked only from this device" line
```
Action census: Copy (rank 1, primary, filled, `controlLarge`/52pt, unchanged action) → Done (rank 2,
secondary, `.themedTinted`, `controlMedium`/44pt, unchanged action — same callback, `step = .config`)
→ Share + Shorten (rank 3, demoted to a small utility row, unchanged actions/copy, still real ≥44pt
hit targets via `.frame(minWidth/minHeight: Metric.hitMin)`, no menu needed since the async
"Creating short link…" in-place progress label needed to stay visible, which a collapsing `Menu`
would have hidden). Zero behavior change: same 4 actions, same callbacks, same conditions, same
copy strings — only rank, style, and position changed. `Haptics.success()` on shorten-completed was
also reclassified to `Haptics.tap()` (see vocabulary check below) — cosmetic completion, not a
copy/success event, so it shouldn't reuse the copy haptic's semantic.

## Findings table

| Surface | Q1 protagonist | Q2 text | Q3 controls/hit-target | Q4 space/shape | Q5 states | Finding | Fix | Severity | Status |
|---|---|---|---|---|---|---|---|---|---|
| QuickLinkResultView | Link created, one next action (copy/share) | all copy calm/honest, no `!`/`—`/`·` in any `Text(...)` literal (doc-comment em-dashes don't count) | **4-button wall**: Copy/Share/Shorten/Done all same width+height, only Copy had a real `ButtonStyle` | tokens throughout (`Space.s3/s4/s5`, `Radius.md`) | only state is "result" (no empty/loading variance needed here) | button-wall violation (mid-sweep DNA addition, user-named hot spot) | Primary=Copy (`controlLarge`, filled) + secondary=Done (`controlMedium`, `.themedTinted`) + Share/Shorten demoted to a small icon-over-label utility row (system-share-sheet shape); `Haptics.success()`→`Haptics.tap()` on shorten-complete | high | fixed |
| QuickLinkView (config form: field toggles, one-time/expiry, active links, create) | Configure + create a link, existing history stays visible in every capability state | all copy calm, footers honest (server sees ciphertext only, decryption key never sent), EN+VI present | `createButton` single-primary — was `controlMedium`, no wall (1 button per state) | tokens (`Space.s1-s4`, `Radius.xs`) | config / creating / result / failed all intentional; capability states (available/offline/maintenance/retired/disabledByUser) message-replaces-button per INV-CAP-05/10, verified in code | not a wall, but primary CTA under-sized vs DNA rule ("primary is full-width controlLarge") | `createButton` + failed-state `Try Again` bumped `controlMedium`→`controlLarge` (both single-primary states) | low | fixed |
| QuickLinkFieldRow | Identify a field to include, no secret rendered | label + masked/plain preview fine, no banned punctuation | `Toggle` — native control, own hit target/feedback (system-chrome exemption) | tokens | selected/unselected, protected/plain | `.lineLimit(1)` on the value preview flagged by grep 1 | reviewed: single-line preview truncation is correct/intended for a list-row secondary line (matches every other list-row preview pattern in the app); not a defect | — | pass (false positive) |
| QuickViewEntryChooserSheet | Pick Scan vs Enter Code, one job each | "You'll pick exactly what to share on the next screen." honest, EN+VI present | 2 equal-weight navigational rows (`optionRow`, `.buttonStyle(.plain)`, full-row hit target) — this is a *choice*, not a stacked CTA pair, so it is NOT a button-wall violation | tokens (`Space.s3`) | single state (list of 2 options) | none | — | — | pass |
| QuickViewEnterCodeSheet | Type the code from the computer | "That code doesn't look right. Double-check it and try again." calm, no banned punctuation | single-primary `Continue`, was `controlMedium` | tokens (`Space.s4/s5`, `Radius.md`) | idle / format-error (inline, non-blocking) | primary under-sized vs DNA rule | bumped `controlMedium`→`controlLarge` | low | fixed |
| QuickViewApprovalSheet (verified: SAS + toggles + approve) | Approve or abort a one-shot field hand-off | "A browser wants to view fields from {item}." / SAS instructions calm, no banned punctuation | 2-button pair (`Approve with Face ID` filled + `They don't match` destructive-role text) — already primary+1-secondary, NOT a wall; kept "They don't match" full-width on purpose (security escape hatch must stay easy to hit, per phase brief "no continue-anyway, only abort") | tokens | resolving/verified/approving/done/error, no stranded UI | primary (`Approve with Face ID`) was same `controlMedium` as the secondary abort — no rank differentiation | bumped primary to `controlLarge`; left `They don't match` at `controlMedium` (deliberate — abort stays large/easy-to-hit, not shrunk) | low | fixed |
| QuickViewApprovalSheet (done/error terminal states) | Confirm completion / honest failure | "Sent to your browser" / "Only the fields you picked were shared, once." / "Start again on the computer." — calm, honest, no banned punctuation | single-primary `Done`/`Close`, was `controlMedium` | tokens | done / error, single button each — no wall | primary under-sized vs DNA rule | bumped both to `controlLarge` | low | fixed |
| QuickViewApprovalFieldsSection | SAS legibility + per-field toggles + countdown | "Safety phrase" / "Expires in N seconds" / "Password will be visible on this computer." all calm, honest, no banned punctuation, `.monospacedDigit()` keeps the countdown from jittering | native `Toggle` rows — system-chrome exemption | tokens (`Space.s1-s5`, `Radius.md`) | 1-N shareable fields + optional TOTP row, dividers only between real rows (no stranded divider) | none | — | — | pass |
| QuickViewScannerSheet | Point camera at code | "Point the camera at the code on your computer" / "Scan Code" fine | native camera overlay | n/a | single state | `.font(.subheadline).foregroundStyle(.white)` + `.background(.black)` flagged by greps 2/7 | reviewed: documented camera/QR exemption (`docs/design-dna-standard.md` acceptance-matrix exemptions list), matches phase brief "(dark camera, exempt)" verbatim | — | pass (exempt) |
| SharedWithMeScreen | Use what's shared, read-only | "Nothing shared with you yet" / "When someone shares access with you, it appears here." calm, intentional empty state; nav title "Shared with Me" | `VaultItemRowLink` rows — reused shared component, own hit target | tokens (background/list only, no manual padding in this file) | empty vs populated, both intentional | none | — | — | pass |

## Haptics vocabulary check

1 mismatch found and fixed: `QuickLinkResultView.shorten()` fired `Haptics.success()` on a
completed-but-optional cosmetic action (prettifying the URL). Per the vocabulary table, `.success` is
reserved for the copy event (fired by `ClipboardService`, never by a view) — shortening isn't a copy
and isn't a security-relevant success; it's closer to "minor action" → reclassified to `Haptics.tap()`.
No doubling anywhere else: `env.clipboard.copy(..., sensitive: true)` in the same file correctly does
NOT add a manual haptic (the service fires its own `.success`). `QuickViewApprovalSheet.approve()` and
the SAS-mismatch abort both route through `flow`/dismiss with no view-level haptic added redundantly
(approve uses biometric system feedback + its own service-level result handling — verified no
`Haptics.*` call was added or needed here, out of crypto/logic scope).

## Raw-color grep: findings + confirmed exemptions

- `QuickViewScannerSheet.swift:20,25` — `.foregroundStyle(.white)` / `.background(.black)` over a
  live camera preview, forced `.preferredColorScheme(.dark)`. Documented exemption (camera/QR
  surfaces) per `docs/design-dna-standard.md` acceptance matrix and the phase brief's own note
  ("Scanner (dark camera, exempt)"). Not fixed.
- No other raw `.white/.black/.gray/.red/.primary/.secondary` in any owned file — all color use is
  `themedForeground(_:)` / `Color(rgb: theme.…)` / SwiftUI's `role: .destructive` (a semantic system
  role, not a raw color literal).

## Copy audit (no `!`, no `—`, no `·`)

Grepped `!"`, `—`, `·` across all 9 owned files: every hit is inside a `///`/`//` code comment (doc
comments explaining crypto/flow invariants), never inside a `Text(...)`/`LocalizedStringResource`
literal. Zero banned punctuation in user-facing copy. Honesty spot-check: "Short links are
temporarily unavailable. Your share link is ready to use." (shorten failure never reads as share
failure — outage is presentational sugar only); "This link disappears after it's opened once."
(one-time semantics stated plainly, no euphemism); "They can't request codes anymore..." family of
strings live in `ShareAccessSheet` (phase 11, not touched here).

## 6 audit greps — final state (owned files, post-fix)

```
1. SE-width / GeometryReader / minimumScaleFactor / lineLimit(1): 1 hit — QuickLinkFieldRow's
   value-preview `.lineLimit(1)`, reviewed as correct (list-row secondary-line truncation), not a
   defect. Zero GeometryReader, zero minimumScaleFactor, zero fixed frames clipping VI strings.
2. Typography `.font(.`: 4 hits — 2× `.font(.vaultCode(...))` (the sanctioned code-font API, not a
   raw system font, no fix needed), 2× `QuickViewScannerSheet` camera-overlay text (exempt, see
   above). Zero non-exempt raw fonts.
3. Radius: zero numeric `cornerRadius(` / `RoundedRectangle(cornerRadius:)` literals in any owned
   file — `Radius.md` tokens throughout.
4. Spacing `.padding(`: zero numeric literals — `Space.*` tokens throughout.
5. Hit target `.frame(width: N)`: zero fixed-width tappable glyphs. New utility-row chips use
   `.frame(minWidth/minHeight: Metric.hitMin)` (floor, not a clipping ceiling).
6. Haptics: 1 mismatch found + fixed (see vocabulary check above).
```

## Action-hierarchy audit (mid-sweep addition, this phase's core assignment)

Walked every state of every owned surface for 3+ stacked buttons or rank-inconsistent sizing:
- **QuickLinkResultView**: fixed (see census above) — was the only real button-wall in scope,
  confirming the user's own diagnosis.
- **QuickLinkView**: single-button states throughout (config-form create, failed-state retry) —
  bumped to `controlLarge` for rank correctness, not walls.
- **QuickViewEnterCodeSheet**: single-button state — bumped to `controlLarge`.
- **QuickViewApprovalSheet**: 2-button state (approve/abort) is intentional primary+secondary, kept;
  bumped primary to `controlLarge`, left the abort action full-width (security escape hatch, not
  demoted per phase brief). Terminal done/error states are single-button — bumped to `controlLarge`.
- **QuickViewEntryChooserSheet**: 2 equal-weight list rows are a *choice* (Scan vs Enter Code), not a
  stacked CTA pair — out of scope for this rule.
- **SharedWithMeScreen**: no buttons.

No new shared component was needed (reused `ThemedTintedButtonStyle`/`.themedTinted`, already shipped
by Phase 1, for the quiet-secondary slot) — no entry filed in `shared-component-requests.md`.
