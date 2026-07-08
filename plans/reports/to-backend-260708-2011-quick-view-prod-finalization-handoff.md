# To Backend — Quick View: remaining items to finalize prod

**Date:** 2026-07-08 · **From:** iOS app team · **Status:** app-side COMPLETE + merged to `main`
(PR #72). E2E verified on staging (scan QR → resolve → approve → seal → browser renders the fields).
Full app suite 409/409, byte-for-byte parity with the frozen vectors.

Thanks for the QR encoder fix — scanning + web render both work now. Below is everything still on the
BE/ops side to take Quick View to production, in rollout order (DEC-QV-ROLLOUT-01, required-before-active).

## 1. Confirm the QR fix is on BOTH envs
- QR now scans on staging. **Confirm the same encoder fix is deployed to the prod `/open` worker** (we
  only exercised staging). Quick sanity: encode any string on prod `/open` and scan with the iPhone
  Camera app — must decode.

## 0. VERIFIED 260708 20:30 — prod status + one gap

Read-only checks against prod:
- ✅ `config.looxpassword.com/v1/capabilities`: `key_id=cap-2026-02`, `schema_version=1`,
  `manifest_version=2`, `quick_view` present + `enabled`. Released schema-1 apps verify it fine.
- ⛔ **`config.looxpassword.com/v1/quick-view/signer-keyset` → HTTP 404 `{"error":"no_document"}`.**
  The prod signer keyset is NOT published. Staging is live (root `cap-2026-02` endorsing
  `qv-session-staging-202607` active). **Without the prod keyset, the app cannot verify a prod SESSION
  envelope → Quick View is non-functional on prod.** `resign-config.sh` does NOT publish this — run the
  separate `publish-quick-view-signer-keyset.sh --remote` for production, and first generate the prod
  runtime session-signer key (`qv-session-production-*`) + `wrangler secret put` it (deploy-checklist
  steps 2–3). Then GET-verify the prod keyset returns 200 with an `active` prod key endorsed by
  `cap-2026-02`.

## 2. Config re-sign to `cap-2026-02` (BOTH envs) — REQUIRED
The app rotated its pinned config trust root to **`cap-2026-02`** (retired `cap-2026-01`). Until the
live capability manifest + domain registry are re-signed with `cap-2026-02`, the app rejects them and
falls back to bundled defaults.
- Run `resign-config.sh staging` then `production` (root key, schema-1 for now — no exposure field
  until the app build ships; see #4).
- Verify: `GET` the manifest + registry on each env and confirm `key_id=cap-2026-02` + signature valid.

## 3. Assertion ladder (per env, upload-assertion is the critical path)
- Staging: move `QUICK_VIEW_ASSERTION_MODE` shadow → required after our device-attest verdicts are
  clean; keep the tripwire (reject any body exposing an un-encrypted key) on.
- Prod: **required-before-active is mandatory** — prod must NOT be `active` while assertion is below
  `required` (worker already 503s this; do not relax).

## 4. Publish manifest schema-2 `exposure` — AFTER the app build ships
Sequencing matters (a schema-1 app can't verify a schema-2 manifest):
- The app build carrying the schema-2 verifier is merged and heading to TestFlight. Once it's on
  testers' devices, publish the manifest with `SCHEMA_VERSION=2 QUICK_VIEW_EXPOSURE=beta` (staging
  first, then prod dark).
- Values: `hidden|beta|ga`, default `hidden`. Keep prod at `beta` (cohort) until assertion=required +
  health verified, then flip to `ga`. Do NOT publish `exposure=disabled` for quick_view (the app
  treats an explicit disabled as a hard hide).

## 5. Regenerate the frozen vectors in base64url (consistency, non-blocking)
The live wire encodes `session_id` / key hashes / nonces / ciphertext / aad as **base64url**, but the
frozen SESSION/PAYLOAD/SAS vectors use **hex**. The app already decodes base64url (we converted our
fixture copies), so this isn't blocking — but please regenerate the vectors in base64url so future
parity tests exercise the real wire on all three sides (app/web/BE).

## 6. Rollout to GA (owner-gated)
```
prod dark deploy → prod beta cohort + shadow → collect App Attest verdicts → assertion=required
→ verify health → flip manifest quick_view.exposure=ga (public GA)
```

## Already resolved (thanks) — no action
- QR encoder (undecodable → fixed).
- `/sessions/resolve` returning `browser_enc_pub` / `browser_sig_pub` (E2E seal now completes).

## 7. Shadow-window upload gating (verify before `required`)
Staging drill (QV-A4) found: in shadow, `POST /sessions/{id}/payload` accepted an upload with **no App
Attest trio** and from a **non-cohort** caller (plain curl) → 200 + claimed the session. That is
expected shadow behavior (accept + record) and the required-before-active ladder closes it — but if the
"shadow accepts beta cohort only" gating (DEC-QV-EXPOSURE-01) is meant to hold during the shadow window,
please confirm the cohort allowlist is actually enforced at `/payload` in shadow. Otherwise anyone who
resolves a session can claim it until assertion goes `required`. (Server state machine otherwise passed:
one-shot claim, ×3 concurrent race exactly-one-winner, expired→404, constant-shape 404, bind-never-blocks.)

## Open questions
1. Is the QR fix already on the prod worker, or staging only?
2. Any prod-only hardening on `/open` (CSP/COOP/COEP headers, no-store) still pending vs staging?
3. Is beta-cohort enforcement at `/payload` intended during shadow (see #7), or only at `required`?
