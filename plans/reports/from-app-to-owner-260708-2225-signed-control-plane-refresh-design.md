# App → Owner: Signed control-plane refresh — design + semantics

Re: "Fix signed control-plane refresh path — Quick View GA exposure stuck hidden".
Root cause accepted. Below = the 5 send-back items. Impl gated on 3 decisions (§6).

## 1. Refresh coordinator design
New `SignedControlPlaneRefresher` (`@MainActor @Observable`), owned by `AppEnvironment`,
wraps the 3 clients (capability manifest, auxiliary domain registry, QV signer keyset).
```
enum Trigger { case launchAfterUnlock, foreground, manual }
func refreshIfNeeded(trigger:) async   // freshness + dedupe gate
func refreshNow() async                // QA/manual, bypasses freshness
```
- Dedupe: single `inFlight: Task?`; concurrent callers join it → one network request
  per document even under launch+foreground race (INV-CP-05).
- Independent failure: each document refreshed under its own `try?`; one failing never
  aborts the others.
- Failure posture: network failure NEVER clears verified cache (INV-CP-03). Clients
  already drop cache ONLY on VERIFY failure (bad sig / expired / wrong-env), never on
  transport failure — unchanged.
- Cancellation-safe `Task`; superseded refresh dropped cleanly. Foreground carries jitter.

## 2. Stale thresholds (proposed; owner-tunable)
- Per-document `lastSuccess` timestamp, persisted, env-scoped.
- launchAfterUnlock: refresh if cache missing OR lastSuccess older than **1h**.
- foreground: refresh if lastSuccess older than **6h**, plus up to **60s jitter**.
- fresh (within threshold) → no network. missing cache → immediate.

## 3. High-water / cache recovery semantics — CURRENT (audited) vs PROPOSED
CURRENT (all 3 clients identical shape):
- `applyCached()` re-verifies cached bytes on relaunch; on verify-fail it DROPS the
  cache (`removeObject`) but leaves `highest_version` in UserDefaults.
- `accept()` rejects `version <= highest` (guard `version > highest`).
- ⇒ **Recovery trap (owner case B) CONFIRMED:** cache lost + BE serving the SAME version
  ⇒ `7 > 7` false ⇒ permanent reject until BE bumps. Device stuck with no usable state.
PROPOSED FIX:
- Relax guard `>` → `>=` (accept `version == highest`). Re-serving the CURRENT version is
  idempotent; strictly-older (`< highest`) still rejected → rollback protection intact;
  high-water is NOT lowered (respects "no self-lower"). Fixes case B, and case A when
  beta/GA collide at the SAME version number.

## 4. Environment scoping — CURRENT (audited) vs PROPOSED
CURRENT: version + cache keys are GLOBAL (no env suffix):
`capability_manifest_highest_version`, `domain_registry_highest_version`,
`quick_view_signer_keyset_highest_version`. Also: capability-manifest URL is
`config.looxpassword.com` for BOTH DEBUG and Release and carries NO in-payload env
binding; domain-registry + signer-keyset DO switch to `config-staging` + bind
`expectedEnv` in DEBUG. ⇒ a DEBUG(staging) container can bump the same global high-water
a Release(prod) container reads (INV-CP-06 violated on dev containers).
PROPOSED: suffix all high-water + cache keys with `<family>_<env>`; capability manifest
gets a build-config env tag for symmetry (URL change NOT proposed — out of scope, needs
BE). See §6 decision on migration.

## 5. Test results — IMPLEMENTED, full suite green
**431/431 pass**, 0 failures (was 409; +22 new). Frozen parity vectors
(`CapabilityManifestTests`, `QuickViewParityTests`, `DomainRegistryDocumentTests`) still
green → the `>=` relax left the signed transcript bytes byte-identical (only the accept
predicate changed).
New coverage:
- `SignedControlPlaneStoreTests` — monotonic advance, equal-version idempotent recovery,
  canonical-hash integrity reject, cache-loss same-version re-accept (the trap), migration
  preserves-not-resets high-water, migration never overwrites newer, env-scope isolation.
- `SignedControlPlaneRefresherTests` — missing→immediate, fresh→skip, stale→refresh,
  sequential launch+foreground = one request, concurrent triggers dedupe to one in-flight,
  launch fires once/process, independent per-family freshness.
- Updated `CapabilityManifestTests` / `DomainRegistryDocumentTests` rollback tests to the
  new invariant (strictly-older rejected; equal admitted).
Manual device QA still owed before merge: real fresh-install launch→GA-appears, and
beta-era cached device foregrounds→GA (simulator can't exercise the App Store cohort flag).

## Implementation summary (what shipped, not yet merged)
- New `SignedControlPlaneStore` — atomic `{version, canonicalHash, bytes, verifiedAt}`
  record per (family, env); reconcile (advance vs hash-gated recovery); idempotent legacy
  migration; refresh clock separate from applyCached (INV-CP-REFRESH-01).
- New `SignedControlPlaneRefresher` — coordinator (freshness, dedupe, per-family backoff,
  foreground jitter); `RefreshableControlPlaneDocument` protocol on all 3 clients.
- 3 clients refactored onto the store; verifier guards relaxed `>`→`>=`.
- `AppEnvironment` owns the refresher; `RootView` fires launchAfterUnlock+foreground
  (non-blocking); `PersonaAliasesScreen` no longer authoritative (routes via `refreshNow`).

## 6. Decisions — LOCKED (owner 260708)
- D1 [P0] Three-way compare, NOT blanket `>=`: `< reject / == verified idempotent recovery
  (full verify + local-canonical-hash equality when available; metric if no local hash) /
  > accept+advance`. Recovery never lowers high-water; no freshness bypass on `==`. Root fix
  = ATOMIC `VerifiedSignedDocumentState { family, env, version, canonicalHash, bytes,
  verifiedAt }`. INV-CP-AR-01..04.
- D2 [P0] Migration PRESERVES high-water (never reset to 0). Keys `control_plane_high_water
  .<family>.<env>`; prod install copies legacy prod value → prod-scoped; idempotent marker
  `control_plane_high_water_migration_v1_done`; no blind cross-env copy. DEC-CP-MIG-01 /
  INV-CP-AR-05.
- D3 Thresholds: missing→immediate; launch age>1h; foreground age>6h +0–60s jitter; age =
  last SUCCESSFUL remote refresh (applyCached never resets it, INV-CP-REFRESH-01); per-family
  backoff (LKG 1m/5m/15m/1h; no-cache 30s/2m/10m). DEC-CP-REFRESH-01.

## Unresolved questions
- Q1 CLOSED by BE: prod beta ≤ v5, GA v6–v7, publish gate rejects candidate ≤ current →
  no version collision; GA v7 safe. No BE version bump needed.
