# QV-A4 — Adversarial Staging Drills Checklist

**Run against:** live staging (`api-staging.looxpassword.com`, shadow assertion). DEBUG build with
launch arg `-quick_view_exposure_override beta`. Automated portion (mutation/parity/exposure/TOTP-edge)
is already green in `VaultifyTests` (409/409); this covers the LIVE server-state + race drills that
unit tests can't.

**Prereq:** BE QR encoder fixed (else use Enter Code for every drill). BE resolve returns
`browser_enc_pub`/`sig_pub` (else the flow stops before seal).

## Helper — create a session via curl (stands in for the browser)

```bash
b64url(){ openssl base64 -A | tr '+/' '-_' | tr -d '='; }
K1=$(openssl ecparam -name prime256v1 -genkey -noout); K2=$(openssl ecparam -name prime256v1 -genkey -noout)
ENC=$(echo "$K1" | openssl ec -pubout -outform DER 2>/dev/null | tail -c 65 | b64url)
SIG=$(echo "$K2" | openssl ec -pubout -outform DER 2>/dev/null | tail -c 65 | b64url)
NONCE=$(head -c 32 /dev/urandom | b64url)
curl -s -X POST https://api-staging.looxpassword.com/v1/quick-view/sessions \
  -H 'content-type: application/json' \
  -d "{\"enc_pub\":\"$ENC\",\"sig_pub\":\"$SIG\",\"browser_nonce\":\"$NONCE\",\"protocol_version\":1}"
# → note human_code + signed_session_envelope.session_id
```

## Drills

- [ ] **Happy path (control):** browser `/open` → app Enter Code → SAS matches → Face ID → "Sent to
  your browser" → browser renders exactly the toggled fields. History row = `item_id+timestamp+result`.
- [ ] **One-shot consume:** after the browser consumes, a second consume of the same session → generic
  failure (no second plaintext). App confirm shows "sent" exactly once.
- [ ] **Session expired (>180s):** create a session, wait past the pre-approval TTL, then approve in
  app → generic "start again on the computer" (no crash, no oracle).
- [ ] **Reused session:** approve once (claims the session), then a second approve/upload → generic
  failure (INV-QV-16: exactly one accepted upload).
- [ ] **Concurrent-approval race:** two app instances (or one app + a scripted upload) approve the SAME
  session near-simultaneously → exactly ONE ciphertext lands; the loser gets a generic failure, handled
  gracefully.
- [ ] **QR-photographed / bind-first drill:** an attacker `bind`s the session first (advisory) → the
  legitimate app approval must STILL win (bind never dead-locks the session; the claim is the upload).
- [ ] **SAS mismatch:** point the app at a DIFFERENT session's code than the one on screen → SAS
  differs → app shows abort-only (no "continue anyway" control exists).
- [ ] **Airplane mid-ceremony:** enable airplane mode after Face ID but before upload completes → calm
  generic error, no partial/committed state; session reusable-or-expired handled by "start again".
- [ ] **Guard2 TOTP:** an item whose TOTP is Extra-Protected → the "Current 2FA code" toggle does NOT
  appear (and never seals guard2 ciphertext).
- [ ] **TOTP window-edge:** approve near a TOTP period boundary → app waits for the fresh window (or
  aborts if the wait would exceed session TTL); the code the browser shows is valid at render time and
  redacts at `valid_until`.
- [ ] **Exposure matrix:** public build (non-beta) with `exposure=beta` → NO entry; `public`+shadow →
  fail closed (no entry); `beta`+beta-cohort → entry present.

## Notes
- Failure discipline: unknown / expired / consumed / foreign-session are indistinguishable (same status
  + generic code) — verify the app shows ONE message for all, never a state oracle.
- Log hygiene: confirm no session_id / code / SAS / plaintext appears in device logs.

## Unresolved
- Race + one-shot drills need either two devices or scripted curl uploads (the app builds the exact
  body: `{ciphertext, app_eph_pub, aad}` base64url + `X-Loox-App-Attest-*` — attestation is shadow so a
  scripted upload without the trio is accepted in shadow, sufficient for the race test).
