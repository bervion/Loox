# Loox Quick View — App Team Proposal
## Zero-knowledge one-shot browser handoff ("Open on Computer")

**Date:** 2026-07-08 · **Status:** Concept + direction APPROVED by owner (review 260708 10:31, ~9/10); this revision incorporates the owner's P0/P1 corrections — byte-level contract freeze is the next gate. Owner decision log at the end supersedes the original open questions.
**Audience:** iOS app team · **Companion:** `backend-proposal-260708-1016-loox-quick-view-session-mailbox.md`
**Owner concept:** iPhone holds the vault → any computer opens `looxpassword.com/open` → QR or short code → app scans/enters → user picks exact fields → Face ID → browser receives ONLY those fields, E2E-encrypted to the browser's ephemeral key. Not "QR login" — an **ephemeral field-scoped encrypted handoff**.

---

## 0. Verdict & how it relates to what we shipped

Architecture is sound and unusually well-specified. It is the **recipient-keyed dual** of Loox Link:

```text
Loox Link   = bearer-URL keyed  (anyone with #k= reads; server-stored ciphertext; TTL days)
Quick View  = recipient keyed   (only THIS browser tab's ephemeral key reads; TTL minutes; one shot)
```

Core security property (INV-QV-02/12): the browser has **no read API over the vault** — it owns an empty
receive session; only the unlocked iPhone mints a fresh ciphertext for that session's key after explicit
per-field approval. IDOR/`item_id`-substitution is impossible by construction, not by validation.

### Verified reuse map (this is mostly assembly, not invention)

| Need | Already shipped | Where |
|---|---|---|
| Field-scoped payload schema + allowlist + default trio + concealed hints | `LooxLinkEnvelope` (TOTP-seed/guard2/attachments hard-excluded by design) | `Vaultify/Features/Sharing/LooxLink/LooxLinkEnvelope.swift` |
| Field-toggle approval UI | `QuickLinkView` toggles + `ShareAccessSheet` capability toggles | `Features/Sharing/` |
| QR scanning | `QRScannerView`/`QRScannerOverlayView`, used by TOTP import, `PairDeviceSheet`, `JoinVaultFlow` | `Features/ItemEditor/`, `Features/Settings/` |
| Signed-server-document verification (envelope over QR/code) | `CanonicalWriter` transcripts + P256 verifier + trusted key set (`cap-2026-01` root) — manifest & domain-registry pattern | `VaultifyCore/Models/CapabilityManifest.swift`, `DomainRegistryDocument.swift` |
| Face-ID foreground ceremony, re-read-then-seal, boundary-aware TOTP current code | `ApprovalCeremonyService` (never pre-sends a future TOTP window) | `Services/Sharing/` |
| App Attest client (register/assert, shadow→required ladder) | `LooxLinkAttestation` + per-surface transcript families | `Features/Sharing/LooxLink/` |
| Optional-capability plumbing (breaker, operator state, manifest) | `CapabilityStore` + signed manifest; add `quick_view` | `Services/Capabilities/` |
| Web-side decrypt+render+Reveal UI | s.looxpassword.com viewer already decrypts AES-GCM and renders `LooxLinkEnvelope` JSON | backend repo, `/open` page reuses |

### Deltas vs the owner concept (analysis findings — each needs sign-off)

1. **Crypto suite must NOT reuse `ApprovalCrypto`'s HPKE.** It runs `Curve25519_SHA256_ChachaPoly`
   (`ApprovalCrypto.swift:92`) — WebCrypto has no ChaCha and no native HPKE. Recommended (D1):
   **frozen P-256 ECDH(ephemeral↔ephemeral) → HKDF-SHA256 → AES-256-GCM**, everything WebCrypto-native
   and CryptoKit-native, with a canonical transcript + frozen vectors (house discipline makes a custom
   KEM acceptable; hand-rolled JS HPKE is more audit surface, not less).
2. **SAS phrase must be DERIVED, not server-issued.** Both sides compute
   `words(HKDF("LOOX-QV-SAS-V1", session_id ‖ enc_key_hash ‖ sig_key_hash))` independently — the server
   cannot equivocate two sessions into one phrase. Honest threat model: SAS defeats **QR relay onto a
   screen the user is physically looking at** (net-café case); it does not defeat a victim who scans an
   attacker's QR from a phishing page AND wants to send secrets to "whatever browser this is" — that
   residual is addressed by explicit browser metadata + field review + the one-shot property.
3. **"Enter Code" lives on the iPhone in V1.** There is no Loox Mac app yet (multiplatform is plan
   260704-1751); the no-camera path = user types the code into the iPhone app. Mac app inherits the
   same protocol later.
4. **TOTP = virtual field, not an envelope field.** `LooxLinkEnvelope.shareableFields` hard-excludes
   TOTP (correct — that guards the SEED). Quick View adds a checkbox "Current 2FA code" whose value is
   the **current 6-digit code**, minted at seal time with `ApprovalCeremonyService`'s boundary rule
   (too close to window edge → wait for fresh window). Never the seed. Off by default.
5. **Upload is a protected mutation** → its own App Attest assertion transcript family
   (`LOOX-APP-ATTEST-QUICK-VIEW-V1`), frozen with vectors BEFORE client code (house rule; shorten-link
   taught us the transcript freeze even pins the endpoint path).
6. **`/open` lives on the canonical domain only.** Auxiliary domains (vexla.app, loox.pw) never host it
   (INV-AD-03 family). The QR carries no callable URL — the app talks to hardcoded canonical endpoints;
   the QR payload is only the signed session envelope.

---

## 1. Protocol (locked shape, pending byte-level freeze)

```text
BROWSER  1. generate ephemeral P-256 enc keypair + P-256 sig keypair (non-extractable, memory-only)
         2. POST create session {enc_pub, sig_pub, browser_nonce} → signed session envelope
         3. render QR (envelope) + human code + SAS phrase; poll/SSE for state
APP      4. scan QR or enter code → (code path: POST resolve {code} → fetch signed envelope)
         5. verify envelope: P256 signature (trusted root), expiry, protocol, key hashes
         6. ADVISORY bind (telemetry/browser-UI "phone connected" only — NEVER exclusive, NEVER
            part of trust; P0-2: exclusive first-scan-wins would let anyone who photographs the QR
            dead-lock the session). Show sheet: browser metadata (informational) + SAS + field
            toggles (defaults per owner: username ON, website ON, password OFF — explicit tick with
            "Password will be visible on this computer." warning; TOTP/notes OFF) —
            item = the one the user is standing on, chosen by APP only
         7. Face ID → RE-READ item → build LooxLinkEnvelope(+virtual TOTP) from EXACT selection
         8. ECDH(app_eph, browser_enc_pub) → strengthened KDF (P0-1):
            kdf_transcript = LOOX-QUICK-VIEW-KDF-V1 ‖ version ‖ session_id ‖
                             browser_enc_key_hash ‖ browser_sig_key_hash ‖ app_eph_pub_hash ‖ env
            HKDF-Extract(salt = SHA256(kdf_transcript)) → HKDF-Expand(info = magic ‖ version ‖ role)
            → AES-256-GCM; AAD binds full context
         9. upload {ciphertext, app_eph_pub, aad_fields} + App Attest assertion over
            canonicalUploadBodyHash (exact body bytes, not just AAD context — P0 fix #4).
            **First cryptographically valid approval upload atomically CLAIMS the session**
            (this — not scanning — is the one-winner point)
BROWSER 10. PoP: sign server challenge with sig key → fetch envelope → decrypt locally →
            verify AAD context → render → atomic consume → memory-only, auto-clear
```

**AAD (`LOOX-QUICK-VIEW-PAYLOAD-V1`)** binds: `session_id ‖ browser_enc_key_hash ‖ approval_id ‖
field_manifest_hash ‖ issued_at ‖ expires_at`. Mix-and-match across sessions/browsers/approvals dies at
the AEAD, not at server policy. `display_title` rides inside the ciphertext (server never sees it).

## 2. Invariants

Adopt INV-QV-01…12 verbatim from the owner concept. Additions:

```text
INV-QV-13  SAS phrase is DERIVED from (session_id, browser key hashes) by both ends
           independently; the server cannot choose or repeat it.
INV-QV-14  /open and the Quick View API live on canonical looxpassword.com hosts only;
           auxiliary domains never participate.
INV-QV-15  The approval upload is App-Attest-bound over a frozen transcript that includes
           the AAD context hash.
INV-QV-16  (REVISED per owner P0-2) Binding is ADVISORY only. The one-winner point is the
           first cryptographically valid approval upload, which atomically claims the
           session; a session stores at most one ciphertext, ever. No scan/bind may
           lock a session against the legitimate approver.
INV-QV-17  The TOTP field carries only a current one-time code minted at seal time,
           boundary-aware; never seed material.
INV-QV-18  The derived payload encryption key MUST be context-bound to the exact browser
           recipient key, browser sig key, app ephemeral sender key, session, environment,
           and protocol version (KDF transcript, not just AAD).
INV-QV-19  SAS mismatch is a HARD BLOCK: the approval sheet offers no "continue anyway".
           SAS is a human confirmation signal (~2^21), never a protocol secret.
```

## 3. UX (V1)

- **Item detail** → toolbar/menu action "Open on Computer" (Polaris icon; localized EN+VI) → chooser:
  Scan QR / Enter Code.
- **Approval sheet** (authorization boundary): browser metadata line, SAS phrase (match instruction —
  mismatch path is abort-only, INV-QV-19), field toggles from `shareableFields` + "Current 2FA code",
  expiry countdown, `[Approve with Face ID]`. Defaults (owner-locked): ☑ Username · ☐ Password
  (ticking shows "Password will be visible on this computer.") · ☑ Website · ☐ Current 2FA code ·
  ☐ Notes. Uses `PolarisModal`/sheet conventions; all strings EN+VI.
- **After approve:** "Sent to your browser" confirmation. Local history row (owner-locked: KEEP,
  minimal): `item_id + timestamp + result` ONLY — no session_id, no field list, no browser metadata,
  no SAS, no code. Renders as "Opened on a computer · Today, 10:42".
- Errors are calm + specific-enough: expired session, already used, mismatch → "start again on the computer".

## 4. App phases

- **QV-A0 — Contract review + freeze sign-off** (no code): reconcile the four frozen artifacts with BE
  (session envelope, payload AAD/KDF transcript, browser PoP, upload assertion). Vectors delivered by BE
  generator that imports production encoders; Swift parity signs off byte-for-byte. GATE QV-1.
- **QV-A1 — Kernel (VaultifyCore):** session-envelope verifier (reuse CanonicalWriter/P256 root),
  SAS derivation + wordlist, ECDH/HKDF/AES-GCM sealer with AAD builder, payload envelope reuse
  (`LooxLinkEnvelope` + virtual TOTP builder). Pure, parity-tested, no UI. After GATE QV-1.
- **QV-A2 — Session client:** resolve-by-code, bind, upload (+`LOOX-APP-ATTEST-QUICK-VIEW-V1`
  assertion, shadow ladder), `quick_view` capability wiring (breaker/manifest/service-state).
- **QV-A3 — UX:** item-detail entry, scanner sheet (reuse `QRScannerView`), enter-code sheet,
  approval sheet with Face ID + re-read + boundary-aware TOTP, confirmation & error states, EN+VI.
- **QV-A4 — Adversarial QA:** tampered envelope, expired/reused session, concurrent-approval race
  (two apps race the claim — exactly one ciphertext lands), QR-photographed-then-bound-by-attacker
  drill (legit approval must still win), AAD/KDF mutation matrix, SAS mismatch drill (abort-only),
  TOTP window-edge, airplane-mode mid-ceremony.
- **QV-A5 — Device QA with live staging** (browser matrix: Chrome/Safari/Firefox/Edge on
  Win/macOS/Linux; SSE vs poll; clipboard warning UX).

## 5. Non-goals (V1)

Passkey handoff (no meaningful browser consumer without WebAuthn) · attachments · multi-item per
session · persistent web sessions / "trusted browser" · browser-initiated field requests · Mac/iPad
native "enter code" surfaces (inherit later) · autofill-into-page (render-only).

## Owner decision log (review 260708 — supersedes the original open questions)

- **D1 suite:** P-256 ECDH + HKDF-SHA256 + AES-256-GCM. No hand-rolled JS HPKE in V1. KDF transcript
  strengthened per P0-1 (INV-QV-18).
- **Bind semantics (P0-2):** advisory bind; **first valid approval wins** — atomic claim happens at
  upload, never at scan.
- **PoP transcript (P1-2):** unified rich transcript (version, operation="consume", session_id,
  challenge_id, challenge, sig_key_hash, issued_at, expires_at, env) — see backend doc B3.
- **Upload assertion (P0 #4):** binds `SHA256(canonicalUploadBody)` (exact bytes), not AAD alone.
- **Resolve-by-code (P1-3):** POST body, never GET query (log/history hygiene).
- **SAS:** keep 2 words + 2 digits as human confirmation signal; mismatch = hard block (INV-QV-19).
- **Defaults:** username ON, website ON, password OFF (explicit tick + visibility warning),
  TOTP OFF, notes OFF.
- **History row:** keep, minimal (`item_id + timestamp + result` only).
- **Guard2-only item:** entry action disabled with explainer.
- **TTLs:** 180 s pre-approval · 90 s post-upload · 5 min render max · 2 min hidden auto-lock.
- **Hosting:** dedicated quick-view worker; SSE primary + long-poll fallback (signaling only).
- **Bind attest:** shadow initially + rate budgets; upload assertion is the critical path.

## Unresolved questions

1. **QR payload density (owner: benchmark before freeze):** variant A = full signed envelope in QR
   (offline-verifiable, denser) vs variant B = compact locator + signed digest, app fetches envelope
   (lighter QR, online-dependent). Pick by real-device scan reliability; result feeds the
   `LOOX-QUICK-VIEW-SESSION-V1` freeze.
2. SAS wordlist source/size (2048-word EN list assumed) — freeze alongside the SAS spec.
