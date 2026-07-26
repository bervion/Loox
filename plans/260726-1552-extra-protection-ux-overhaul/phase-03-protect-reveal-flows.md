# Phase 03 — Protect / reveal / unprotect flows

## Protect sheet (`ProtectFieldSheet.swift` rebuild)
- Header names the field ("Protect Email").
- Two option cards (not a bare segment): "Extra Password" (one password for all protected fields, unlocks once per session) vs "Custom code" (this field only, asked every time) — one-line explanation each.
- No Extra Password yet → the Extra Password card shows "Set it up now" inline navigation to the Phase-02 screen (sheet over sheet or push), never a text-only dead end; default selection falls back to Custom code.
- Cancel button; Protect CTA bottom (BrandCapsuleCTA), not a toolbar chip.
- TOTP caveat line when protecting a TOTP field (live code stops, autofill excluded).

## Locked row (`ProtectedFieldRow.swift`)
- Scheme-aware label: "Protected with Extra Password" / "Protected with custom code" (+ lock glyph); menu offers Remove Protection even while locked (prompts for the secret first, then confirm).
- Remove Protection: confirmation dialog always ("The value returns to normal visibility.").

## Reveal prompt (`CodePromptSheet.swift`)
- Per-scheme title/copy; the instruction is a subhead, not a pill; field placeholder matches the secret name; autofocus; Cancel button; error names the right credential.

## Terminology sweep
- EN: feature "Extra Protection", credential "Extra Password", per-field "Custom code" — no "Level-2" in user-facing strings.
- VI: "Mật khẩu cấp 2" everywhere (fix the two "bảo vệ nâng cao" drifts); "Mã riêng" for custom code.

## Validation
- Full loop on sim: no-password start → protect (inline setup) → lock/unlock → reveal both schemes → remove protection with confirm → editor state unchanged.
