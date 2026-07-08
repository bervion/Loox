---
phase: 3
title: "Session Client + App Attest + Capability (QV-A2)"
status: pending
priority: P1
effort: "1.5d"
dependencies: [2]
---

# Phase 3: Session Client + App Attest + Capability (QV-A2)

## Overview

Networking + attestation + capability plumbing. App-only code under
`Vaultify/Features/Sharing/QuickView/` (DeviceCheck must not leak into the appex — same
placement rationale as LooxLink ADR). Talks ONLY to hardcoded canonical endpoints
(`api.looxpassword.com/v1/quick-view/…`); QR payload is never a callable URL (INV-QV-14).

## Architecture

Endpoints consumed by app (backend doc §B2):
```text
POST /sessions/resolve       {code} in BODY (never GET query) → signed_session_envelope
POST /sessions/{id}/bind     ADVISORY only — telemetry/"phone connected"; failure NEVER blocks approve
POST /sessions/{id}/payload  {ciphertext, app_eph_pub, aad_fields…} + X-Loox-App-Attest-* trio
                             first valid upload atomically claims (server-side)
GET  /v1/quick-view/service-state   capability health probe
```
- Attestation: `LOOX-APP-ATTEST-QUICK-VIEW-V1` transcript per Phase-1 freeze —
  `u16len(method) ‖ u16len(path) ‖ u16len(challengeId) ‖ u16len(session_id) ‖
  SHA256(canonicalUploadBody)`. Fresh challenge per attempt (server consumes on verify —
  shorten rule). Model register→assert lifecycle on `LooxLinkAttestation` (`generateKey → persist
  keyId → attest-once register → assert per request`, one invalid-key retry budget —
  `LooxLinkAttestation.swift:10-12`) so first-upload registration is handled, not a failure mode.
  Shadow posture initially: send headers when supported, server not yet required-mode; independent
  per-surface ladder. Bind gets shadow assertion too (cheap).
- **Cohort-gated exposure (DEC-QV-EXPOSURE-01, F2):** the signed manifest carries a three-state
  `quick_view.exposure = disabled | beta | public`. Entry visibility is multi-layer, NOT a UI flag
  alone (a custom client bypasses UI):
  - `disabled` → no entry point, any assertion mode.
  - `beta` → entry shown only to a gated beta cohort (TestFlight/internal build gate); backend
    accepts uploads from beta cohort while assertion is in shadow, records verdicts.
  - `public` → entry shown to eligible users ONLY when backend assertion = required; if manifest says
    public while assertion still shadow, **fail closed** (INV-QV-24).
  App reads exposure from the signed manifest via `CapabilityStore`; the beta-cohort determination is
  an app build/cohort gate (e.g. TestFlight vs App Store build). INV-QV-16 (reworded): a session
  accepts exactly one accepted upload; public-mode acceptance requires REQUIRED App Attest; shadow
  uploads only for gated beta cohorts. **Backend dependency:** the cohort allowlist + "shadow accepts
  beta-only" rule live in the backend companion doc (flag to BE — app cannot enforce alone).
- Failure discipline: expired/consumed/unknown come back indistinguishable — map to one
  generic user-facing error ("start again on the computer"), no state-specific branching.
- DEBUG base-URL override via UserDefaults (mirror `loox_link_api_base_url` convention).

## Related Code Files

- Create: `Vaultify/Features/Sharing/QuickView/QuickViewAPIClient.swift`
- Create: `Vaultify/Features/Sharing/QuickView/QuickViewAttestation.swift` (register/assert; model on `LooxLinkAttestation.swift`)
- Create: `Vaultify/Features/Sharing/QuickView/QuickViewCanonical.swift` (upload-body canonical serialization + assertion transcript builder)
- Create: `Vaultify/Features/Sharing/QuickView/QuickViewConfig.swift` (endpoints, TTL constants)
- Modify: `VaultifyCore/Models/Capability.swift` — add `case quickView = "quick_view"` to enum
  **`CapabilityID`** (F6 — the enum is `CapabilityID` `Capability.swift:6`, NOT `Capability`)
- Modify: `Vaultify/Services/Capabilities/CapabilityHealthProbe.swift` — add a `case .quickView`
  to the `readyURL(for:)` switch (`CapabilityHealthProbe.swift:12`) pointing at the **dedicated
  quick-view worker** service-state URL (its own worker per owner decision — do NOT reuse the shared
  loox-link `/v1/link/service-state` that `shareLink`/`shortLink` use)
- Read for pattern: `LooxLinkAPIClient.swift`, `LooxLinkAttestation.swift`, `LooxLinkCanonical.swift`, `CapabilityStore.swift`
- Create: `VaultifyTests/QuickViewClientTests.swift` (canonical body vectors, assertion transcript parity, resolve/upload decode, generic-failure mapping)

## Implementation Steps

1. `QuickViewConfig` — canonical endpoints, TTLs (180s/90s), size cap 16KB, DEBUG override.
2. `QuickViewCanonical` — canonicalUploadBody encoder (frozen field order from Phase 1) +
   assertion transcript builder; parity-test against vectors byte + clientDataHash.
3. `QuickViewAPIClient` — resolve (POST body), bind (fire-and-forget advisory), upload
   (attest trio headers), service-state probe. Logging: path+status only, never bodies/codes.
4. `QuickViewAttestation` — key register/assert, fresh challenge per attempt, shadow ladder
   flag (`quickViewAssertionRequired=false` initially).
5. Capability wiring: `quickView` in `CapabilityID`, manifest gating via `CapabilityStore`,
   breaker/service-state messages (`quick_view_maintenance|disabled|retired`). Read the
   `quick_view.exposure` three-state from the signed manifest; resolve visible entry =
   `f(exposure, assertion-required signal, build-cohort)` per the DEC-QV-EXPOSURE-01 matrix
   (fail-closed on public+shadow).
6. `tuist generate` + `make check` + `make test`.

## Success Criteria

- [ ] Assertion transcript + canonicalUploadBody parity green vs frozen vectors
- [ ] Bind failure demonstrably does not block upload path (unit test)
- [ ] All error variants collapse to one generic user-facing failure
- [ ] `quickView` added to `CapabilityID` (correct enum) + distinct quick-view service-state URL
- [ ] `quick_view` capability gates the feature via signed manifest; outage never touches core vault
- [ ] Three-state `exposure` resolves entry per DEC-QV-EXPOSURE-01 matrix; public+shadow fails closed (INV-QV-24)
- [ ] `make check` + `make test` pass

## Risk Assessment

- Endpoint path is pinned inside the assertion transcript — a path change post-freeze breaks
  attestation (shorten-link lesson); keep path as a single constant referenced by both client
  and transcript builder.
- Never persist session_id/code/SAS anywhere (history row comes later and excludes them).
- Exposure gating is only as strong as its weakest layer — app must NOT rely on UI-hide alone;
  the manifest `exposure` + backend cohort allowlist are the load-bearing gates (DEC-QV-EXPOSURE-01).

<!-- Updated: Validation Session 1 — DEC-QV-EXPOSURE-01 three-state cohort-gated exposure replaces binary GA gate (INV-QV-16 reworded, INV-QV-24 added) -->

## Unresolved questions

- Exact manifest field name/encoding for `quick_view.exposure` — freeze with BE in Phase 1
  (part of the capability-manifest contract, not a new artifact).
