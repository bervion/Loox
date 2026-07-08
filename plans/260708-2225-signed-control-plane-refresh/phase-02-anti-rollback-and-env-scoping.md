# Phase 02 — Anti-rollback recovery + env scoping

Priority: P0 · Status: pending · Depends: none (parallel with Phase 01)

## Problem (verified)
- Case B recovery trap: `applyCached` drops cache on verify-fail; `highestAcceptedVersion`
  persists. `accept` rejects `version <= highest` → cache-lost + same-version served =
  permanent reject. Guard: `CapabilityManifest.swift:192` (`> highestAcceptedVersion`);
  same shape in DomainRegistryVerifier / QuickViewSignerKeysetVerifier.
- Case C env scoping: version keys global (not env-suffixed). Capability manifest URL is
  prod for BOTH configs and carries no env binding; domain-registry + signer-keyset switch
  to staging in DEBUG. A dev DEBUG(staging) container can contaminate the global high-water.

## LOCKED decisions (owner 260708)

### D1 — three-way version comparison (NOT a blanket `>=`)
```
incoming.version <  highest  → REJECT (rollback)
incoming.version == highest  → MAY re-accept ONLY as verified idempotent recovery
incoming.version >  highest  → ACCEPT + advance high-water
```
The `==` branch runs the FULL verification first (signature, document family, env,
schema, trusted key, issued_at sane, freshness policy, canonical decode) — never
`version == highest → auto accept`. Equal-version recovery MUST NOT lower/reset/modify
high-water. Do NOT frame this as "fixes beta/GA collisions" — same-version content
mutation is NOT tolerated. (BE confirmed: prod beta ≤ v5, GA v6–v7, publish gate rejects
candidate ≤ current going forward → no collision; v7 safe.)

### Canonical-hash guard on the `==` branch
- When a canonical hash for the high-water version is stored locally, equal-version
  recovery MUST require `SHA256(incoming.canonicalBytes) == storedHash`; mismatch =
  hard reject / integrity incident.
- When no local hash (true storage loss), re-accept after full verify, and emit metric
  `control_plane_same_version_recovery_without_local_hash`.
- Do NOT bypass freshness on `==`; an expired equal-version doc follows family stale policy.

### Atomic storage (root fix — `>=` alone is symptom relief)
Persist ONE atomic record so "cache lost + high-water remains" cannot occur:
```
VerifiedSignedDocumentState { family, environment, version, canonicalHash,
                              signedDocumentBytes, verifiedAt }
```
Atomic replace (single UserDefaults key holding the encoded record), not separate
cache-bytes + high-water keys that can desync.

### D2 — migration: PRESERVE high-water (option 2), never reset to 0
- Key shape: `control_plane_high_water.<family>.<env>` (family AND env).
- Production App Store: copy legacy prod high-water → prod-scoped key. Do NOT copy to staging.
- Idempotent, guarded by marker `control_plane_high_water_migration_v1_done`; never
  overwrite a newer scoped value; never blindly max across envs.
- DEBUG runtime-switchable endpoints: if provenance mixed/unknown, scope to the current
  configured env only (or drop legacy for dev). No blind copy to prod.

## Invariants (freeze)
- INV-CP-AR-01 version < high-water → MUST reject.
- INV-CP-AR-02 version == high-water → MAY re-accept only as idempotent recovery after
  full signature/family/env/schema/freshness validation.
- INV-CP-AR-03 equal-version recovery MUST NOT lower/reset/modify high-water.
- INV-CP-AR-04 when a local canonical hash for high-water exists, equal-version recovery
  MUST require exact hash equality.
- INV-CP-AR-05 a storage-schema migration MUST NOT lower a known high-water when its
  environment provenance is known.

## Files
`CapabilityManifest.swift`, `DomainRegistryDocument.swift`, `QuickViewSignerKeyset.swift`
(verifier accept predicate + canonical-bytes exposure for hashing); the 3 clients
(atomic state record, family+env keys, idempotent migration); tests.

## Todo
- [ ] Three-way compare in accept path (all 3 families) with `==` recovery gate
- [ ] Canonical-hash equality check on `==` branch + missing-hash metric
- [ ] Atomic VerifiedSignedDocumentState record (replaces split cache/version keys)
- [ ] family+env-scoped keys + idempotent legacy migration (marker, no reset)

## Success
- Cache-lost + same-version (hash-match, or no local hash) → verified recovery, no stuck state.
- version < high-water → rejected; high-water never lowered by migration/recovery.
- Staging never contaminates prod high-water.
