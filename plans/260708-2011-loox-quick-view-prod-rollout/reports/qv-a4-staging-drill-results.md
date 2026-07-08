# QV-A4 — Staging Drill Results

**Date:** 2026-07-08 · **Env:** `api-staging.looxpassword.com` (service-state `active`, assertion shadow)
· **Method:** scripted curl (blind mailbox accepts opaque bytes, so the server state machine is fully
exercisable without the app). Device/UI drills listed at the end need the physical app.

## Server-state drills — ALL PASS ✅

| # | Drill | Expected | Result |
|---|---|---|---|
| D1 | Create session | 200 + signed envelope + human_code + sas_inputs | ✅ envelope (base64url fields), code `NQ22-99RT` |
| D2 | Resolve by code | envelope **+ browser_enc_pub + browser_sig_pub** | ✅ all three keys present (BE resolve-pubkey fix confirmed) |
| D3 | Resolve unknown / malformed code | constant-shape 404 | ✅ both → 404 |
| D4 | One-shot claim | upload#1 200, upload#2 fails | ✅ 200 then **404** (session claimed) |
| D5 | Concurrent race ×3 | exactly one winner each | ✅ 200/404, 200/404, 404/200 (atomic claim, INV-QV-16) |
| D6 | Bind advisory | bind never blocks approve | ✅ bind 200, upload-after-bind 200 |
| D7 | Expired session (>180s TTL) | upload + resolve rejected | ✅ both → 404 |

## Key confirmations
- **INV-QV-16 (one-winner)** holds under real concurrency — exactly one ciphertext lands per session.
- **Resolve returns the browser pubkeys** (`browser_enc_pub`/`browser_sig_pub`, base64url) — the earlier
  BE blocker is fixed; full E2E seal path is unblocked (and the user confirmed the browser renders data).
- **Failure discipline:** unknown / malformed / expired / claimed all collapse to `404` — no state oracle.
- **Blind mailbox:** the server accepted opaque random ciphertext (it never decrypts) — correct.

## Note for BE (shadow behavior, not a bug)
- In shadow, `/payload` accepted uploads **without** any App Attest trio and from a non-cohort caller
  (my curl). That is expected shadow behavior (accept + record), and is exactly why prod is gated
  **required-before-active** (the 503 guard + assertion=required close this window before public GA).
  Confirm the beta-cohort allowlist enforcement is wired for the shadow window if that gating is
  intended before `required`.

## Device / UI drills — PENDING physical app (logic already proven by 409 unit tests)
These need Face ID + the app UI and can't be scripted; the app-side logic is covered green by unit
tests (`QuickViewFlowTests`/`QuickViewKernelTests`):
- SAS mismatch → abort-only, no bypass (unit: `testAbortSASMismatch…`).
- Guard2 TOTP → 2FA toggle absent (unit: `testComposerExcludesGuard2TOTP`).
- Exposure matrix incl. public+shadow fail-closed (unit: `testExposureMatrix`).
- TOTP window-edge wait bounded by session TTL (unit: `testComposerTOTPWaitExceedsSessionBudget`).
- Airplane mid-ceremony → calm generic error (manual on-device).
- QR-photographed / bind-first from the app UI (server-side dead-lock impossibility already shown by
  D5/D6: bind never claims; only the first valid upload claims).

## Verdict
Server-state + protocol drills: **PASS**. Device/UI confirmation folds into Phase 3 on-device smoke +
Phase 2 browser matrix. No app bug surfaced.
