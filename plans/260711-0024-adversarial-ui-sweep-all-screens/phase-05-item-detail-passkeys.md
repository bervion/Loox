# Phase 5 — Item Detail + Passkeys

**Status**: done · **Wave**: W2 · **Owns**: `ItemDetail/*`, `Passkeys/*` (22 surfaces).
ItemDetail reworked by prior pass → REGRESSION re-review; Passkeys fresh. Method = canonical protocol + 6 greps.

## Protagonist
Item Detail = "use this credential". Progressive disclosure: Layer A (title/username/password/OTP) immediate,
Layer B (website/notes/attachments) contextual, Layer C (history/metadata/delete) behind menu / below fold.

## Cluster hotspots
- **DetailFieldRow / TOTPFieldRow**: tap-to-copy anywhere → single `Haptics.success` from `ClipboardService`;
  the row must NOT add its own haptic. TOTP grouped `123 456` + countdown ring (amber ≤10s/red ≤5s roles).
  Secret pre-reveal uses `SpoilerText`/glyph-resolve, fixed-length mask (never leak length, rule 9).
- **BottomCopyPasswordCluster**: thumb-zone F1 cluster — hit targets ≥44, one-handed reachable.
- **ProtectedFieldRow / ProtectFieldSheet / CodePromptSheet**: "Protected — tap to reveal"; reveal needs L2
  or custom code; risky reveal → `Haptics.warning`; wrong-code error inline (no alert), honest copy.
- **SharedAccessGateView (6 states)**: not-granted / authenticated / offline / verifying / unverifiable+Try-Again
  / revoked — secret value NEVER renders before the gate passes. Each state intentional, no stranded layout.
- **LargeTypeView**: full-screen character grid, tap-to-mark, Copy, TOTP ring header — legible at all Dynamic
  Type sizes; color cells semantic.
- **LocatedInSheet**: Space pill picker. **AttachmentFieldRow**: "EXT · size" — replace the `·` interpunct
  with real layout (two lines or label+value) per rule 8.
- **PasskeyDetailSheet / ItemPasskeysSection / SharedItemPasskeysSection / PasskeysScreen**: backup-status
  badge (Backed up / Backup eligible / This device only) via roles; Delete Passkey → dialog "permanently
  destroys the private key" (honest, no `!`); shared passkey NEVER exposes private key.
- Toolbar: destructive "Move to Trash" belongs in the "…" menu (Layer C), appears once, with confirm.

## Deliverables / Todo
`reports/phase-05-findings.md` · `strings-manifest-phase-05.md` · fixes.
- [x] Protocol answers (16 owned surfaces + `SharedAccessGateView`). [x] 6 greps. [x] Verify NO copy-haptic doubling in any field row (confirmed: single fire in `ClipboardService`).
- [x] Walk all 6 SharedAccessGate states + attachment `·` removal (already resolved). [x] Passkey delete confirm honesty (already compliant).
- [x] Fixes + manifest (15 fixed: 4 high/7 medium/4 low; 2 deferred — see findings report).

## Success / Risk
Success: audit-grep clean; secrets masked fixed-length and never render pre-gate; destructive actions once,
in menu, confirmed; OTP a typographic object; EN+VI. Risk: prior-pass regression (Med×Med) diff-first;
gate-state edits must not weaken the "no secret before gate" invariant (security > cosmetics).
</content>
