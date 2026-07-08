---
phase: 4
title: "Approval UX + Scanner + Enter Code (QV-A3)"
status: pending
priority: P1
effort: "2d"
dependencies: [3]
---

# Phase 4: Approval UX + Scanner + Enter Code (QV-A3)

## Overview

User-facing flow: item detail → "Open on Computer" → scan QR / enter code → approval sheet
(authorization boundary) → Face ID → re-read → seal → upload → confirmation. Item is ALWAYS the
one the user is standing on — chosen by app only, never by browser/server.

## Requirements

- Entry action on `ItemDetailScreen` (Polaris icon, localized EN+VI). **Guard2-only item →
  action disabled with explainer** (owner-locked).
- Chooser: Scan QR (reuse `QRScannerView`) / Enter Code (format `XXXX-XXXX`, Crockford-minus-
  `0O1IL` charset validation client-side; resolve via Phase-3 client).
- Approval sheet contents: browser metadata line (informational), **SAS phrase** with match
  instruction — mismatch path is ABORT-ONLY, no "continue anyway" (INV-QV-19) — field toggles,
  expiry countdown (180s), `[Approve with Face ID]`.
- Toggle defaults (owner-locked): ☑ Username · ☐ Password (ticking shows "Password will be
  visible on this computer.") · ☑ Website · ☐ Current 2FA code · ☐ Notes. Field list = the toggleable
  rows from `LooxLinkEnvelope.shareableFields(of:)` PLUS a separate "Current 2FA code" checkbox
  (only if the item has a TOTP seed). **The 2FA checkbox is NOT a `shareableFields` entry** (F4):
  `shareableFields` hard-excludes `.totp` (`LooxLinkEnvelope.swift:35-40`) and `Field` has no `id`,
  so the virtual TOTP cannot be modeled through `selectedFieldIDs`/`build()`.
- **Payload composer (DEC-QV-FIELD-01):** a dedicated Quick View composer owns final-payload
  assembly — `LooxLinkEnvelope` is NOT modified. Face ID → RE-READ item →
  `LooxLinkEnvelope.build(item:selectedFieldIDs:)` for the shareable selection → map into typed
  `QuickViewApprovedField` (kernel model) → if 2FA toggled, APPEND a `QuickViewApprovedField`
  (`kind:.currentTOTP`) AFTER the persisted fields → freeze the ordered array (persisted in envelope
  order, virtual last) → `QuickViewFieldManifest.hash(fields)` (structural, INV-QV-25) → seal
  (Phase-2 kernel) → upload (Phase-3). Do NOT route TOTP through `shareableFields`/`build`; do NOT
  hash before appending (AAD must bind the FINAL array).
- **Boundary-aware TOTP mint (F1):** current code via `TOTPGenerator`; window check via
  `TOTPIssuancePolicy`/`TOTPWindow` (`ApprovalModels.swift:335`). The wait loop is Quick-View-owned
  (do NOT call `ApprovalCeremonyService` — CKShare/ChaCha-bound, `ApprovalCrypto.swift:92`). Too
  close to period edge → wait for fresh window; never a future code, never the seed (INV-QV-17).
- **TOTP `valid_until` metadata (DEC-QV-TOTP-01/INV-QV-26):** the minted currentTOTP field carries
  its exact window-end `valid_until` as authenticated payload metadata (inside the ciphertext /
  AEAD-bound — never plaintext-mutable). The `/open` page counts down and redacts the code after
  `valid_until`; other fields stay until the 5-min render TTL. App's job = mint code + set exact
  `valid_until`; the countdown/redaction is BE/web (flag to BE).
- **Wait vs TTL (F7):** the post-Face-ID boundary wait (up to ~1 period) consumes the 180s session
  budget. Bound the wait by remaining session TTL — if waiting for a fresh window would exceed the
  session expiry, abort to "start again on the computer" rather than seal-then-fail-at-upload.
- Advisory bind fires on scan/resolve success (spinner-free; ignore failures).
- After approve: "Sent to your browser" confirmation. Errors calm + generic: "start again on
  the computer".
- **Local history row (minimal):** `item_id + timestamp + result` ONLY — no session_id, field
  list, browser metadata, SAS, or code. Renders "Opened on a computer · Today, 10:42" in item
  history. Device-local store — **reuse the existing store pattern** (`LooxLinkRecordStore` +
  `KeychainStore`, `Features/Sharing/LooxLink/LooxLinkRecordStore.swift`) rather than inventing a
  net-new store type (F10); keep the schema to the three fields.
- All strings EN+VI in `Localizable.xcstrings`; titles `.inAppLocalized`; runtime `appString()`.
  Design tokens only (Space/Radius/Metric/`.vaultType`), Polaris icons, 44pt targets.

## Related Code Files

- Create: `Vaultify/Features/Sharing/QuickView/QuickViewEntryChooserSheet.swift`
- Create: `Vaultify/Features/Sharing/QuickView/QuickViewEnterCodeSheet.swift`
- Create: `Vaultify/Features/Sharing/QuickView/QuickViewApprovalSheet.swift`
- Create: `Vaultify/Features/Sharing/QuickView/QuickViewApprovalFlowModel.swift` (state machine: scan→verify→bind(advisory)→approve→seal→upload→done/error)
- Create: `Vaultify/Features/Sharing/QuickView/QuickViewPayloadComposer.swift` (build shareable → map to typed fields → append virtual TOTP → freeze order → manifest hash)
- Create: `Vaultify/Features/Sharing/QuickView/QuickViewHistoryStore.swift` (minimal rows; modeled on `LooxLinkRecordStore`)
- Modify: `Vaultify/Features/ItemDetail/ItemDetailScreen.swift` (entry action + guard2 gate)
- Reuse: `Vaultify/Features/ItemEditor/QRScannerView.swift` (`onFound:(String)->Void`),
  `LooxLinkEnvelope.swift` (`build`/`shareableFields`), `VaultifyCore/Sharing/ApprovalModels.swift`
  (`TOTPWindow`/`TOTPIssuancePolicy`), `TOTPGenerator` — NOT `ApprovalCeremonyService`
- Modify: `Localizable.xcstrings` (EN+VI)

## Implementation Steps

1. Flow model + states; wire kernel verify → SAS compute → sheet.
2. Entry action + guard2-disabled explainer on `ItemDetailScreen`.
3. Scanner + enter-code sheets (validate charset/checksum before resolve).
4. Approval sheet: metadata, SAS (abort-only mismatch button "They don't match"), toggles with
   defaults + password warning, countdown, Face ID button.
5. Ceremony via `QuickViewPayloadComposer`: Face ID → re-read → `build()` shareable → map to typed
   fields → append virtual TOTP (boundary-aware, Quick-View-owned loop, wait bounded by session TTL,
   sets `valid_until`) → freeze order → structural manifest hash over full list → seal → upload.
6. Confirmation + generic error states; history row write on result.
7. Localization EN+VI; light/dark/Reduce-Motion/contrast pass.
8. `tuist generate` + `make check` + `make test`.

## Success Criteria

- [ ] Guard2-only item: entry disabled + explainer
- [ ] SAS mismatch = hard abort, no bypass control exists in UI
- [ ] Password toggle shows visibility warning; defaults match owner lock exactly
- [ ] Sealed envelope contains exactly the toggled fields (re-read, not stale copy)
- [ ] Composer assembles final array; `LooxLinkEnvelope` unchanged; manifest hashed AFTER append (DEC-QV-FIELD-01)
- [ ] TOTP virtual field: current code only, boundary-aware, off by default; carries AEAD-bound `valid_until` (DEC-QV-TOTP-01); wait bounded by session TTL (F7)
- [ ] History row contains only item_id+timestamp+result
- [ ] Every new string has EN + VI; `make check` passes

## Risk Assessment

- Countdown vs Face ID prompt overlap: if session expires mid-Face-ID, upload gets generic
  failure — surface "start again" not a crash; test airplane-mode mid-ceremony (Phase 5).
- Don't cache the decrypted item across the Face ID boundary — re-read is the invariant.

<!-- Updated: Validation Session 1 — DEC-QV-FIELD-01 Quick-View composer (LooxLinkEnvelope unchanged, typed fields, structural manifest); DEC-QV-TOTP-01 field-level valid_until -->

## Unresolved questions

None. Composer + field model land in Phase 2 (kernel) and are wired here.
- TOTP validity (F7b → resolved DEC-QV-TOTP-01): field-level expiry, NOT payload-wide. App mints
  code + exact AEAD-bound `valid_until`; `/open` counts down + redacts the code after it, other fields
  stay to 5-min render TTL. App surfaces the requirement; the countdown/redaction UI is BE/web.
