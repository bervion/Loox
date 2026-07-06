# Optional Network Capabilities — Full A0–A7

Source: app-team proposal (260706). User locked: **Full A0–A7, both capabilities** (Share Link + Private Email).

## Verified ground truth (both repos, 260706)

- **BE enforcement (B1/B2) LIVE on BOTH workers** (`loox-relay/src/capability.ts`, `loox-link/src/capability.ts`):
  service modes `active|degraded|maintenance|disabled|retired`, per-operation gate (create dies first;
  read/delete/revoke survive maintenance/disabled), problem+json `code` (`capability_maintenance|disabled|
  operation_disabled|retired`) + `X-Loox-Service-State` + `Retry-After`; retired = **410**. `/health/ready`
  returns state. → The app consumes THIS contract; client-side gates must mirror, never widen (BE enforces).
- **Signed manifest (B3) NOT deployed on either worker** → A2 ships verification core + cache + bundled
  fallback + fetch that fails gracefully (404 ≠ retirement, INV-CAP-07); contract draft goes to BE.
- Already satisfied by design (audited): no startup remote fetch anywhere (`RelayFeature` compile-time);
  no global backendAvailable flag; alias/inbox/share-history are local sealed records (visible offline);
  extension has zero relay calls; owned AutoFill independent of capability state.

## Phases → PRs

| PR | Phases | Content | Status |
|----|--------|---------|--------|
| C1 | A0+A1+A3 | Pure capability model + resolver (BE-parity op table) + circuit breaker; `CapabilityStore` (@MainActor: user pref, persisted operator mode, health, connectivity, breakers); structured problem+json parsing in BOTH clients; RelayService/LooxLink wiring + breaker gate; A0 audit | ✅ PR #53 |
| C2 | A2 | Manifest verification core (payload_b64+sig P256, key set w/ key_id, schema+timestamps+anti-rollback), cache, bundled fallback, graceful fetch primary→secondary; BE contract draft | ✅ PR #54 |
| C3 | A4+A5+A6+A7 | `CapabilityStatusBadge`/`CapabilityUnavailableView`/action gating; screen-open `/health/ready` probe (non-blocking); Settings ▸ Online Features (pref ≠ operator; outage never flips pref); retired UX + Review Affected Accounts; App Group snapshot for extension; chaos QA checklist | ✅ PR #55 |

## Invariants enforced in code/tests

- INV-CAP-01/02/06: no startup/AutoFill dependency on capability fetch (A0 audit + snapshot fallback).
- INV-CAP-03: two independent stores/breakers — no shared flag (INV-CAP-08).
- INV-CAP-04: offline / outage / maintenance / disabled / retired distinct (resolver + copy tests).
- INV-CAP-05/10: `read` operation is NEVER gated by resolver (local records always visible).
- INV-CAP-07: 404/timeout/DNS never map to retired; only verified 410/problem+json/manifest can.
- INV-CAP-09: user preference stored separately; operator outage never mutates it.
- Breaker counts ONLY infra failures (timeout/DNS/reset/502/503/504 **without** capability code);
  401/409/cap/validation and structured capability 503s are excluded.

## External dependency

- BE B3 manifest endpoint — contract draft in `manifest-contract-draft-for-be.md`; until then the
  fetch path no-ops onto cache→bundled fallback (all-active default).
