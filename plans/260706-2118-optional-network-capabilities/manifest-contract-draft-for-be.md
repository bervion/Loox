# [Loox] B3 Signed Capability Manifest — contract draft (app → BE)

App-side verifier is SHIPPED and dormant (empty trusted key set → every fetch rejected →
bundled all-active defaults; fail-safe). To activate: BE implements below, hands over key(s),
app ships them in `CapabilityManifestVerifier.bundledTrustedKeys`.

## Endpoint

- Primary: `GET https://api-relay.looxpassword.com/v1/capabilities/manifest` → 200, `Cache-Control: no-store`
- Secondary (later): same signed bytes published to an independent failure domain
  (CloudKit public DB). One semantic manifest, two mirrors.

## Wire envelope (JSON)

```json
{
  "payload_b64":  "<base64 of the raw payload JSON bytes>",
  "signature_b64":"<base64 of 64-byte raw P256 ECDSA over the EXACT payload bytes>",
  "key_id":       "k1"
}
```

- Signature covers the raw payload bytes → **no canonicalization anywhere** (client verifies
  received bytes, then decodes). Same P256/64-byte-raw conventions as the relay transcript.
- `key_id` selects from the app's shipped trusted key set → rotation = publish with a new
  key_id already present in the app's set; never a single eternal key.

## Payload

```json
{
  "schema_version": 1,
  "manifest_version": 42,
  "issued_at_unix_ms": 0,
  "expires_at_unix_ms": 0,
  "capabilities": {
    "private_email": {"mode": "active", "retry_after": 900},
    "share_link":    {"mode": "active"}
  }
}
```

- `mode` ∈ `active|degraded|maintenance|disabled|retired` — the SAME vocabulary as the
  workers' `capability.ts` (manifest = distribution; the worker gate stays enforcement —
  a stale manifest can never widen access).
- `manifest_version` strictly increases on every publish (app enforces anti-rollback:
  rejects any version < highest accepted).
- Suggested TTL: expires 24–72 h after issue; republish on every mode change AND on a cron.
- Unknown capability keys are ignored by the app (forward compatible).

## App behavior (already implemented)

- Verify: signature → key set → schema==1 → issued≤now<expires → anti-rollback.
- Accepted → cached (survives relaunch, re-verified on load) + modes applied as operator
  policy (health/breakers untouched).
- Any fetch/verify failure (404/timeout/bad sig/rollback) is SILENT: cache → bundled
  defaults; never blocks startup; never read as retirement (INV-CAP-02/07).

## BE deliverables to freeze

1. Endpoint + publish pipeline (mode change → new manifest, version++).
2. P256 signing key(s) generated; public x963 + key_id handed to app.
3. 3 test vectors: valid envelope; tampered payload; rollback pair (v N, v N-1).

## Unresolved questions

- Secondary mirror timing (CloudKit public DB) — app treats it as later, non-blocking.
- Per-operation overrides in manifest (narrower than mode defaults) — proposed OUT for v1;
  the worker gate already carries per-operation semantics.
