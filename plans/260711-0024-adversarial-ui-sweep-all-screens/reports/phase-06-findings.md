# Phase 6 — Item Editor: Findings

Scope: 12 View surfaces (+ 2 non-View: `QRScannerOverlayView` UIKit drawing, `GenerateChipSurface`
ViewModifier) across `Vaultify/Features/ItemEditor/*`, per `reports/phase-00-surface-registry.md`
Phase-6 rows. Method: `docs/design-dna-standard.md` adversarial protocol Q1-5 + the 6 audit greps.
Protagonist for the whole cluster: "capture this credential correctly with minimum friction."

## Findings table

| Surface(s) | File | Q1 protagonist | Q2 text | Q3 controls/hit-target | Q4 space/shape | Q5 states | Finding | Fix | Severity | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| ItemEditorScreen, `EditorHeaderActions`, `RotationReminderSection` | ItemEditorScreen.swift | One job: get title + fields in with the fewest taps; Save disabled until title-or-a-field is filled, X→discard-confirm guards accidental loss. First glance (Space pill, avatar, title) serves it; nothing competes. | "Discard changes?" / "Add an email first" / "Couldn't reach the relay" all calm, no `!`/`—`/`·`; VI already present + fits SE | header Save/X are shared `HeaderIconButton`/plain buttons (44pt, Phase-1 territory, out of scope); **badge overlay `.padding(4)` off-grid (FIXED → `Space.s1`, identical value)** | tokens throughout (`Radius.md` via token, `Space.s2/s3/s4`) | new/edit, with/without Space, with/without email-suggestion row, with/without alias-error alert — all intentional; save-disabled + discard-dialog states walked and both correct | 1 trivial spacing defect | `.padding(4)`→`.padding(Space.s1)` | low | fixed |
| ItemEditorScreen (flat `Fields` section: note/card/identity/sshKey/recoveryCodes/securityQuestions/custom) | ItemEditorScreen.swift:141-168 | Non-login categories' "Add Field"/"Add Attachment" rows | n/a | **HIGH: bare `Label` inside the `Menu`/`Button` — tap only registers on the icon+text, not the row** (the sibling `LoginEditorSections.actionRowLabel` helper already documents and fixes this exact defect 40 lines away in the same folder, but the flat editor — used by 7 of 8 categories — never got it) | n/a | affects every non-login category's Add Field / Add Attachment row | dead tap zone on the majority of the row for the app's most-used non-login category action | added `.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())` to both labels, matching the existing sibling fix | high | fixed |
| ItemEditorScreen (Space pill / "Located In"-style dropdown) | ItemEditorScreen.swift:263-288 | quick-switch the item's Space | "No Space" fine | pill's own tappable background is ~38pt tall (< 44pt `hitMin`) | `Space.s3`/`Space.s2` padding around a 22px badge | n/a | identical pattern (padding values, radius, structure) to `ItemDetailScreen`'s already-reviewed (Phase 5) "Located In" pill — a Phase-6-only fix would diverge from that screen's accepted look | not fixed here — flagged for Phase 15 to consider tuning both screens together for consistency, since Phase 5 is a different (frozen this wave) owner | low (consistency, cross-phase) | deferred, cross-phase note |
| LoginEditorSections (Credentials/Websites/Custom/Notes sections, passkey row) | LoginEditorSections.swift | Group login fields into true semantic cards (not decoration); passkeys tap→detail, no delete-with-flicker | section headers = plain `Section("…")` (localized); passkey row copy fine | Add Website/Add Field/Add Attachment rows already correctly full-width-tappable (`actionRowLabel`); passkey row is a full `Button` wrapping the whole `HStack` — correct | tokens throughout (`Space.s2/s3`) | credentials/websites/custom/notes each independently empty-or-populated; linked-passkey list empty/1/many — all render distinct, no stranded sections | none | — | — | pass |
| EditorFieldRow, `GenerateChip`, `GenerateChipSurface` | EditorFieldRow.swift | Edit one field's label+value with the right keyboard, masked when it's sensitive | "Protected. Manage in the item view" honest, no banned punctuation; per-kind placeholders ("Enter password"/"Enter website"/…) all present+VI | scan-QR button already 44pt (`Metric.hitMin` frame); **generate chip and reveal-on-focus rely on tap targets already ≥44** | **6× raw `.font(.caption/.subheadline/.body)` (FIXED → `vaultType`)**; row `.padding(.vertical, 2)` off-grid (see note below) | empty/filled/focused/unfocused/extra-protected/edit-mode(reorder) all intentional | **HIGH: masking only covered `.password`/`.totp` — a `protected` `.monospace` field (Card Number, Security Code, ID Number, from the Card/Identity templates) rendered in full plaintext the whole time it's edited, in the wrong (non-`vaultCode`) font, unlike its own masked/`vaultCode` rendering in the detail view (`DetailFieldRow.isSecret = field.protected \|\| field.kind.isSecret`)** — storage-encrypted values sat unmasked on screen with no controlled-reveal treatment while editing | generalized the existing password/TOTP mask+reveal-on-focus scaffold to `case _ where field.protected` (covers any protected single-line kind); font ternary now uses `VaultType.body.font`/`Font.vaultCode()` instead of raw `.body`; 6 typography raw-`.font` sites → `vaultType` | high (masking, fixed) / medium (typography, fixed) | fixed |
| WebsiteFieldRow | WebsiteFieldRow.swift | Type a bare domain → offered the full https URL + favicon | "https://example.com" placeholder is `verbatim` (intentionally not localized — it's a literal example URL); suggestion chip text `verbatim` (a URL, correctly not localized) | suggestion chip is a full `Button` around the whole `HStack`, `contentShape(Capsule())` — correct | **2× raw `.font(.body)` (FIXED → `.vaultType(.body)`)**; row `.padding(.vertical, 2)` off-grid (see note) | empty/typed-bare-domain(chip shown)/typed-full-URL(chip hidden) all intentional | 2 typography defects | fixed | medium | fixed |
| TagChipEditor | TagChipEditor.swift | Add/remove tags with minimum ceremony | "Add tag" placeholder fine, dedup case-insensitive, no banned punctuation | **HIGH: remove-tag `×` button's hit box was the bare 11pt glyph — no padded hit area at all (design-dna rule 6's exact example: "a small glyph button gets an invisible padded hit area, never a 20pt tap target")** | **raw `.font(.subheadline)` (FIXED); `.padding(.horizontal, 10).padding(.vertical, 6)` — off-grid, didn't match the app's established chip convention (`FilterChip`: `Space.s3`/`Space.s2`)** | empty (hidden)/1 tag/many tags (horizontal scroll) — all intentional | 3 defects | font→`.vaultType(.subhead)`; padding→`Space.s3`/`Space.s2` (aligns with `FilterChip`); remove button hit area expanded via `.contentShape(Rectangle().inset(by: -(Metric.hitMin-11)/2))` (same technique the Phase-1 orchestrator already approved for `RevealableSecureField`'s reveal glyph) — visual glyph stays 11pt, tappable region grows toward 44pt without resizing the chip; some vertical bleed is edge-clipped by the horizontal `ScrollView`, still a meaningful improvement over the original bare-glyph box | high (hit-target, fixed) / medium (typography/spacing, fixed) | fixed |
| TOTPScannerSheet | TOTPScannerSheet.swift | Get a 2FA secret in fastest: scan, or photo, or paste | "Point the camera…", "That doesn't look like a 2FA setup code.", "No QR code found in that image." — calm, honest, no banned punctuation, already `appString`-wrapped + VI present | "Choose a screenshot" full-width `.buttonStyle(.bordered)`; inline paste `Button("Add")` — compact but native system-button hit-padding, acceptable for an inline field-adjacent action | **3× raw `.font(.subheadline/.footnote/.body)` (FIXED → `vaultType`)**; `.padding(.bottom, 28)` tied to the camera overlay's own geometry (bracketArm/hole offsets in `QRScannerOverlayView`) — camera-surface exemption, not a generic magic number | camera-available / Simulator(no camera, still shows overlay+fallbacks) / photo-no-QR-found / manual-paste-invalid — all give distinct, honest errors | 3 typography defects | fixed | medium | fixed |
| QRScannerView (iOS `UIViewControllerRepresentable` + camera controller) | QRScannerView.swift (iOS branch) | Live QR detection with Telegram-style focus snap | n/a (no text; haptic on found: `UINotificationFeedbackGenerator().notificationOccurred(.success)` — a system (not `Haptics.*`) call, correct since this predates/parallels the app's own vocabulary for the same "success" event, not doubled) | n/a (full-screen camera, exempt) | camera preview + overlay fill the screen; `.black` background = documented camera exemption | granted/denied permission, code-found/not-found, entry animation — all covered | none | — | — | pass |
| QRScannerView (macOS placeholder), `QRScannerOverlayView` (UIKit) | QRScannerView.swift (macOS branch), QRScannerOverlayView.swift | macOS has no camera path — tell the user to use iPhone/photo/paste instead | "Scan on iPhone" / "Use a photo or paste the setup key below instead." calm, honest | n/a (static text) | **2× raw `.font(.headline/.footnote)` (FIXED); bare `.padding()` (FIXED → `Space.gutter`, identical default value)**; `QRScannerOverlayView` raw `UIColor.black/.white` — camera-surface exemption (documented), correct as-is | macOS-only fallback vs iOS live scan — both intentional | 3 defects (macOS branch only) | fixed | low | fixed |
| ItemIconPickerSheet | ItemIconPickerSheet.swift | Pick one Polaris icon for the item's avatar | "Choose icon" / "Done" fine | grid buttons already `Metric.hitMin` framed — correct | tokens throughout (`Radius.sm`, `Space.gutter/s2`) — no defects | selected/unselected icon highlight both intentional; 5-col grid reflows correctly at SE (flexible `GridItem`s, no fixed width) | none | — | — | pass |
| AttachmentPickerSheet | AttachmentPickerSheet.swift | Add a file from Files or Photos | **HIGH: `error = "Couldn't open the file."` / `"Couldn't read the file."` are raw Swift `String` literals assigned to a `@State String?`, never routed through `appString()` — unlike this file's own `TOTPScannerSheet` sibling, which does it correctly. Confirmed via the catalog: both keys are entirely MISSING (no EN, no VI) — these two error strings can never localize to Vietnamese, violating the project's mandatory EN+VI rule.** | Choose File / Choose Photo rows are full `List` rows (system-sized, ≥44pt) — correct | raw `.font(.footnote)` (FIXED) | success / permission-denied(no file selected)/ read-failure — read-failure path was the unlocalized one | wrapped both in `appString(...)`; added to strings manifest with EN+VI | high (localization, fixed) | fixed |

## Known gap confirmed (not fixed, per phase instruction)

**Date fields render as plain text.** Confirmed at `VaultifyCore/Models/ItemCategory.swift:76`
(Identity template: `DynamicField(label: "Date of Birth", kind: .date)`) and
`EditorFieldRow.swift`'s `kindEditor` — `.date` has no dedicated case, so it falls into the generic
`default:` branch: a plain `TextField` with the generic "Enter value" placeholder, default keyboard
(no `UIDatePicker`/`.date`-style component), no format validation. This is a feature gap (needs a
`DatePicker`-based row + a date-formatting decision), not a token/copy/spacing fix — logged per the
phase brief's instruction, not implemented here.

## Deferred (documented, not fixed this pass)

- **Space-pill hit target** (ItemEditorScreen) — see table row above; identical to `ItemDetailScreen`'s
  accepted pattern, needs a cross-phase (5+6) decision, not a unilateral Phase-6 change.
- **Multiline-protected fields (SSH Private Key, Recovery Codes) stay unmasked while editing.** The
  masking generalization applied to `EditorFieldRow` intentionally excludes `.multiline` (matched first
  in the `switch`) — a masked multi-line editor needs its own UI (can't reuse the 16-bullet single-line
  mask), which is a larger, separate change. Noted for a future pass; the values are still encrypted at
  rest, only the on-screen editing view is unmasked (consistent with pre-existing behavior, not a
  regression from this pass).
- **`.padding(.vertical, 2)`** — used identically 3× (`EditorFieldRow`, `LoginEditorSections` passkey
  row, `WebsiteFieldRow`) as the row's own micro breathing space inside `Form`/`List` rows. Off the
  `Space` 4pt grid (nearest is `Space.s1`=4, double the current value) — left as-is: it's a deliberate,
  consistently-repeated convention across 3 files, not a stray magic number, and doubling every field
  row's padding is a visible density change better decided app-wide (Phase 15) than patched piecemeal.

## Haptics vocabulary check

All 5 `Haptics.*` call sites are in `ItemEditorScreen.swift`: `.success` on save / attachment-add /
private-email-created, `.error` on save-failure / attachment-save-failure. All match the vocabulary
(destructive/failure → error, successful mutation → success) and none double an event the service
layer already fires (`ClipboardService` isn't invoked anywhere in this phase's files). No defects.

## Raw-color grep: false positives / confirmed exemptions

- `QRScannerView.swift`, `QRScannerOverlayView.swift`, `TOTPScannerSheet.swift` camera-preview
  branch: `.black`/`.white`/`UIColor.black`/`UIColor.white` — all inside the full-screen camera
  surface, a documented exemption (`design-dna-standard.md` → "camera/QR … surfaces").
- `EditorFieldRow.swift` `Color.primary.opacity(0.12)` (glass-capsule hairline stroke, 2 sites) —
  not a themed color but a neutral hairline explicitly by design (comment: "so the chip outline
  stays clean in both light and dark"), same rationale as the ambient-shadow exemption Phase 1
  already documented for `Elevation`. Not a defect.
- All other `.secondary`/`.primary` matches are `themedForeground(.secondary)` /
  `ThemeRole.primary` calls (semantic token API), not raw SwiftUI colors.

## 6 audit greps — final state (owned files, post-fix)

```
1. SE-width / GeometryReader / minimumScaleFactor / lineLimit(1): only intentional single-line
   truncations (folder-name pill, attachment name, passkey rows) + the one legitimate
   GeometryReader (GenerateChip anchor positioning). No clipping risk found at SE width for the
   longest VI strings checked (all verified present in the catalog).
2. Typography `.font(.` : only `.font(.vaultCode())` remains — the correct MonoLisa token, not a
   raw system font. All previously-flagged raw `.font(.caption/.subheadline/.body/.headline/
   .footnote)` sites (17 total across 6 files) converted to `.vaultType(_:)`.
3. Radius: zero numeric literals — both `RoundedRectangle(cornerRadius:)` sites already used
   `Radius.sm`/`Radius.md` tokens.
4. Spacing `.padding(`: 4 numeric literals remain, all reviewed and either fixed (trivial,
   identical-value swaps) or deliberately left (see "Deferred" section above for rationale).
5. Hit targets: 2 HIGH findings (TagChipEditor remove button, ItemEditorScreen flat-editor
   Add Field/Add Attachment rows) fixed; 1 cross-phase note filed (Space pill).
6. Haptics: 5 call sites, vocabulary-correct, no doubling (see above).
```
