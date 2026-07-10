# Phase 12 — Sharing: Quick Link + Quick View + Shared-with-Me

**Status**: pending · **Wave**: W2 · **Owns**: `Sharing/QuickLink*`, `Sharing/QuickView/*`,
`Sharing/SharedWithMeScreen.swift` (10 surfaces). Method = canonical protocol + 6 greps (`phase-01`).

## Protagonist
Quick Link = "make an encrypted link anyone can open, safely, with limits". Quick View = "hand one field to a
browser, once". Shared-with-Me = "use what someone shared, read-only".

## Cluster hotspots
- **QuickLinkView / QuickLinkFieldRow**: per-field toggles with masked preview ("••••••••" for secrets; TOTP +
  extra-protected never shareable — dim via role, not raw gray). One-time toggle → expiry picker; footer copy
  differs one-time vs expiring; Active-links list + swipe-revoke + honest dialog ("Anyone who has the link loses
  access immediately."). Create button reflects capability (Available/Offline/Maintenance/Retired/user-off) —
  message replaces button, history stays.
- **QuickLinkResultView**: the ONLY place the decrypt key exists — "Link ready", shortened URL centered,
  scope warning, expiry line (amber "disappears after it's opened once" via role), Copy/Share/Shorten/Done.
  Shorten failure → "Short links are temporarily unavailable" (share still worked, honest).
- **QuickView/ (5 sheets)**: EntryChooser (Scan / Enter Code) → Scanner (dark camera, exempt) → EnterCode
  (`XXXX-XXXX` mono auto-format, error "That code doesn't look right.") → ApprovalSheet + ApprovalFieldsSection.
  Approval: SAS safety-phrase card, "Expires in N seconds" countdown, per-field toggles (enable Password →
  warning "Password will be visible on this computer."), Approve-with-Face-ID, red "They don't match" (no
  continue-anyway), states resolving/verified/approving/done/error (all errors → one honest "Start again on the
  computer."). Verify no `!`/`—`/`·`.
- **SharedWithMeScreen**: empty "Nothing shared with you yet" intentional; list → read-only detail (Phase 5 owns
  the detail screen + gate; this phase owns only the list surface).

## Deliverables / Todo
`reports/findings-phase-12.md` · `strings-manifest-phase-12.md` · fixes.
- [ ] Protocol answers (10). [ ] 6 greps. [ ] Walk QuickLink capability-button states + QuickView state machine.
- [ ] Non-shareable/masked previews via role. [ ] SAS + expiry legibility at SE. [ ] Fixes + manifest.

## Success / Risk
Success: audit-grep clean; secret previews masked; capability states message-not-crash; QuickView SAS/expiry
legible; EN+VI. Risk: QuickView is one-shot E2E security (High×High) — presentational only, never touch the
SAS/approve/expire logic; masked previews must never render the real secret.
</content>
