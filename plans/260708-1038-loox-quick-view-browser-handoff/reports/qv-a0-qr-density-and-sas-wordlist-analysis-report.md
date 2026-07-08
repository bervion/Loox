# QV-A0 — QR Density + SAS Wordlist Analysis (app-team pre-freeze inputs)

**Date:** 2026-07-08 · **Phase:** QV-A0 (Phase 1) · **Status:** app-side analysis DONE; device
benchmark + BE artifact review PENDING. Feeds `DEC-QV-QR-01` (QR carrier freeze) + SAS spec freeze.

Scope: the two app-team-owned unresolved questions that gate the SESSION/QR freeze. Does NOT close
GATE QV-1 (needs BE draft artifacts + vectors + physical-device scan runs).

---

## 1. QR density — variant A vs B (computed byte budgets)

Byte-mode QR capacity → version (modules). Lower modules = easier scan on old cameras / glare / low light.

| Carrier | raw B | base64 B | QR ver (ECC-M) | modules | Offline ECDH? |
|---|---|---|---|---|---|
| **A** full envelope, **hashes only** | 250 | 336 | v11 | 61×61 | ❌ NO (see §1.1) |
| **A** full envelope **+ browser pubkeys** | 252 | 336 | v12 | 65×65 | ✅ yes |
| **B** locator + truncated digest(16) | 52 | 72 | v4 | 33×33 | ❌ (fetch) |
| **B** locator + full digest + server sig | 136 | 184 | v8 | 49×49 | ❌ (fetch) |

(Envelope field budget: magic 8 · version 2 · session_id 32 · enc/sig key 32+32 (hash) or 33+33
(compressed pubkey) · browser_nonce 24 · server_nonce 24 · issued_at 8 · expires_at 8 · env 4 ·
key_id 12 · P256 sig 64. QR sent in byte mode — do NOT base64 into the QR; encode raw bytes.)

### 1.1 Design gap surfaced (freeze-critical, flag to BE)

SESSION-V1 as drafted in backend §B3 carries **key HASHES** (`enc_key_hash ‖ sig_key_hash`), not the
keys. But the app needs the **actual** `browser_enc_pub` (P256 point) to run `ECDH(app_eph,
browser_enc_pub)`. Consequence:

- **Hashes-only envelope in QR is NOT offline-usable** — the app still must fetch the real pubkeys →
  that is variant B in disguise (no offline advantage, just a bigger QR at v11).
- **Genuinely-offline variant A** must carry the compressed pubkeys in the QR → v12 (65×65), the
  hardest to scan.

So the honest choice is: **A = carry pubkeys, v12, offline** vs **B = carry locator+digest, v4–v8,
one fetch**. A "hashes-only" middle is the worst of both (big QR, still needs a fetch).

### 1.2 Recommendation (pre-benchmark)

Data supports the owner's lean toward **B**: v4–v8 vs v12 is a large scannability gap on strangers'
machines (net-café / poor screens), and the feature is already network-dependent (bind/upload/poll),
so a SESSION fetch barely dents the "offline" property. The QR digest binds the fetched envelope to
what the user scanned (integrity preserved). **Still gate the final call on the device benchmark
threshold: choose A only if success ≥ 99% AND p95 scan < 2s on target devices; else B.**

### 1.3 Device benchmark protocol (run before QR-V1 freeze)

Generate real QR images at: **A** = v12 payload, **B** = v4 (truncated-digest) and v8 (full-digest+sig)
payloads. Scan matrix:
- Devices: oldest supported iPhone (slow autofocus) + a mid + a current.
- Screens showing the QR: Windows laptop low brightness, macOS glossy w/ glare, Linux.
- Conditions: 20/40/60 cm; bright + dim; light + dark page theme; small + medium QR render size.
- Browsers rendering `/open`: Chrome, Edge, Safari (density/anti-alias differs).
- Metrics per cell: time-to-first-success, success rate, retry count, false decodes, min practical size.
- Decision: A if (success ≥ 99% ∧ p95 < 2s) across target-device cells, else B.

(Concrete payload generation waits on BE's frozen SESSION-V1 byte layout, or use representative
random bytes at the exact sizes above to benchmark scannability now — the bytes are opaque to the
scanner, so size is the only variable that matters for reliability.)

---

## 2. SAS wordlist spec

### 2.1 Shipped list (verified)

`Vaultify/Resources/eff_large_wordlist.txt` = **7772 words**, single word per line, no blank/dupe
lines (`grep -c`, `uniq -d` clean). Loaded today by `DicewareWordList.words`
(`VaultifyCore/PasswordGenerator.swift:5-8`): `Bundle.main.url(forResource:"eff_large_wordlist")` →
`split(whereSeparator:\.isNewline)`. Reusable for SAS (Quick View is app-side → `Bundle.main` valid).

### 2.2 Freeze-critical mismatch (flag to BE/web)

- The code comment `PasswordGenerator.swift:3` says "7776 words" — **stale; the file is 7772**. The
  standard EFF large list is 7776. **This shipped file is a 7772-word variant, NOT canonical EFF.**
- SAS derives independently on app + web/BE and must match **byte-identical**. Therefore BE/web MUST
  use the EXACT SAME 7772-word file (ship it as a shared artifact), NOT the canonical EFF 7776 — or
  all three sides re-align on one canonical list. **Freeze the exact file + word order as a shared
  contract artifact.** (Do not assume "EFF list" — the count differs.)

### 2.3 Proposed derivation (2 words + 2 digits, owner-locked shape)

```text
material = HKDF-SHA256(ikm = "LOOX-QV-SAS-V1",
                       salt/info = session_id ‖ enc_key_hash ‖ sig_key_hash)   # exact order per B3
# take 34 bits: 2 words (13 bits each, index mod 7772) + 2 digits (00–99)
w1 = words[ u16(material[0..2]) % 7772 ]
w2 = words[ u16(material[2..4]) % 7772 ]
dd = u16(material[4..6]) % 100
SAS = "{w1} {w2} {dd:02d}"
```
- Entropy ≈ 2·log2(7772) + log2(100) ≈ 12.92·2 + 6.64 ≈ **32.5 bits** (owner cited ~2^21 as the
  floor for a human confirmation signal; 7772-word list exceeds it comfortably — fine).
- Exact byte-offset scheme + `mod` vs rejection-sampling + word count (7772) must be frozen with BE
  so both ends land the same phrase. Modulo bias at 65536 % 7772 is negligible for a comparison
  signal; keep `mod` for simplicity unless BE prefers rejection sampling (freeze whichever).

---

## Open items (need BE / physical devices — NOT app-team-closable now)

1. **BE draft artifacts + vectors** for all 8 (SESSION/QR/CODE/PAYLOAD/FIELD-MANIFEST/POP/APP-ATTEST/
   SAS) — none exist in this repo yet; GATE QV-1 can't close until delivered.
2. **SESSION-V1 pubkey question (§1.1)** — BE must decide: envelope carries compressed pubkeys
   (enables offline variant A) or only hashes (forces a fetch = variant B). Drives the A/B freeze.
3. **Physical-device QR benchmark (§1.3)** — needs real devices + screens; run before QR-V1 freeze.
4. **Shared wordlist artifact (§2.2)** — BE/web must adopt the exact 7772-word file, or all re-align.
5. **`quick_view.exposure` state + cohort allowlist** encoding in the capability manifest (DEC-QV-EXPOSURE-01).
6. **TOTP `valid_until`** placement in the PAYLOAD-V1 plaintext schema (DEC-QV-TOTP-01, AEAD-bound).
