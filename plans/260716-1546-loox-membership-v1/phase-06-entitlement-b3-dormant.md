# Phase 6 — Entitlement B3: dormant client integration

**Status:** IMPLEMENTED 260717 (branch `feat/entitlement-b3-dormant`).
**Contract:** BE handoff `looxpassword-web/plans/reports/from-backend-to-app-team-260716-entitlement-b3-integration-handoff.md` (contract_version 1) + the three Q&A answers (parity vectors added; `no_subscription_state` = retryable, report if recurring; App Store dark / TestFlight open confirmed).
**Everything is dormant:** backend runs `ENTITLEMENT_MODE=off`, purchases stay dark for App Store users; this phase exists so grants/leases/telemetry are already true when enforcement flips (B5).

## What shipped

- `LooxEntitlementAttach.swift` — config (staging for DEBUG, prod for Release;
  the app never declares an environment), attach request/response models
  (snake_case wire), error taxonomy per contract §2/§4, `LooxBindingHash`
  (SHA-256 hex of canonical UTF-8, no normalization).
- `LooxEntitlementCoordinator.swift` — `appAccountToken` Keychain store with
  restore-adoption from the verified transaction; single-flight attach with
  backoff (retryable + `no_subscription_state` ≤3 strikes); grants held in
  memory until replaced (idempotent server-side); leases per service —
  Sandbox memory-only, Production persisted locally (never synced); lazy
  re-attach on lease expiry (no polling); `LooxEntitlementClientHooks`
  (payload provider + refresh handler) and `RelayPrincipalWireIdentity`.
- Service wiring: relay (`entitlement` top-level sibling OUTSIDE the frozen
  signed transcript, read server-side after consumeNonce; refresh-required
  re-attaches then loops with a FRESH nonce; 429 `quota_exceeded` split from
  the abuse budget), link + quick view (`entitlement` in the asserted body —
  transcript-safe because both canonicals bind named fields, not raw bytes;
  refresh-required → attach → ONE retry with a fresh assertion).
  `X-Loox-Entitlement-Contract: 1` rides whenever a payload is attached.
- Paywall: `purchase(options: [.appAccountToken(...)])` from the very first
  purchase; attach triggers on purchase success, restore, every verified
  `Transaction.updates` delivery, refresh-required, and lease expiry.
- Attest keyId accessors (`LooxLinkAttestation.storedKeyId`,
  `QuickViewAttestation.storedKeyId`) + relay publishes its wire principal id
  (std-b64 WITH padding — the exact string the backend hashes).
- `LooxEntitlementContractTests` — the three FROZEN parity vectors, the
  no-normalization property, and attach wire-shape pins.

## Deliberately not here (per contract)

`binding_conflict` support UI (B4), `Set App Account Token` defensive flow
(pending ASC verification), iCloud Keychain token sync (V1 accepts
restore-per-device), any UI consuming attach results.

## Verify before B4

BE runs their §8.2 (attach E2E with a REAL Sandbox purchase) against the first
TestFlight build of this branch; watch for the coverage header in their logs.
