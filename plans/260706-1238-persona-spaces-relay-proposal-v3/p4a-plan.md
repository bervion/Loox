---
title: "P4A — Relay Security Foundation (iOS client half)"
description: "On-device Relay Principal (P256), signed commands, epoch + escrow — no backend, no network."
status: done
priority: P2
effort: 9h
branch: feat/persona-p4a-relay-principal
tags: [relay, crypto, cloudkit, security, persona]
created: 2026-07-06
---

# P4A — Relay Security Foundation (iOS CLIENT ONLY)

On-device security primitives for the email relay: a user-owned **Relay Principal**
(long-lived P256 signing key, distinct from App Attest device identity), canonical
**signed commands**, and minimal **epoch** machinery. NO worker, NO network, NO live
alias activation. Everything compiles + unit-tests locally with sync OFF.

Scope source: `proposal-v3-locked-decisions.md` D2/D3/D4/D5, INV-R01/R02/R04.
Blueprints cloned: `ParticipantEscrowService`, `ParticipantIdentity`, `ApprovalCrypto`
(`DeviceSigningIdentity`, `CanonicalWriter`), `LooxLinkCanonical` (parity vectors).

## Invariants carried into every phase
- **INV-R01** App Attest MUST NOT be the long-lived owner of relay resources — the Principal is.
- **INV-R02** A relay command is authorized by the current Principal epoch AND independently
  admitted by App Attest. Two SEPARATE layers — this phase builds ONLY the Principal layer.
- **INV-R04** (note only) hot path enforces epoch; cron never enforces. Backend concern.

## Phases (dependency-ordered)

| # | Phase | Effort | Blocks on | Status |
|---|-------|--------|-----------|--------|
| 1 | [Principal crypto core + escrow codec](p4a-phase-01-principal-crypto-core.md) | 3h | — | pending |
| 2 | [Signed RelayCommand + parity vectors](p4a-phase-02-signed-command-parity.md) | 3h | P1 (principalID/epoch) | pending |
| 3 | [Escrow service + rotation + erase wiring](p4a-phase-03-escrow-service-erase.md) | 3h | P1, P2 | pending |

## Data flow (one screen)
```
Vault unlocked (vaultKey) ──▶ RelayPrincipalEscrowService.ensurePrincipal(vaultKey)
   ├─ Keychain fast-cache hit ──▶ RelayPrincipalIdentity (P256 + epoch + principalID)
   ├─ CloudKit "Vault" zone escrow hit ──▶ decode ──▶ cache
   └─ miss ──▶ generate P256 ─ derive principalID=SHA256(MAGIC‖x963 pub) ─ seal(vaultKey)
              ─ first-writer-wins create ─ cache
RelayPrincipalIdentity ──▶ sign(RelayCommand) ──▶ (transcript LOOX-RELAY-AUTHZ-V1, signature)
                       ──▶ rotate() ──▶ (newIdentity epoch+1, signed rotate cmd) ──▶ escrow overwrite
Erase Vault ──▶ eraseRemote() drops "Vault" zone (escrow dies) + clearLocalCache()
```

## Key files created
- `VaultifyCore/Relay/RelayPrincipalIdentity.swift`, `RelayPrincipalState.swift`, `RelayConfig.swift`
- `VaultifyCore/Relay/RelayCommand.swift`, `RelayCommandCanonical.swift`
- `Vaultify/Services/Relay/RelayPrincipalEscrowService.swift`
- `VaultifyTests/Fixtures/relay-authz-command-vectors-v1.json`
- Tests: `RelayPrincipalIdentityTests`, `RelayCommandCanonicalTests`

## Out of scope → DEFERRED to P4B (backend/worker)
Live client API client, worker `workers/loox-relay/`, network sends, `disable-all` durable
ack, alias activation (`RelayFeature.activeAliasesEnabled` STAYS false), rate-limit/kill-switch
enforcement, cron, offline-block-erase UX (D4 — only relevant once active aliases exist),
backend CAS epoch enforcement, App Attest admission wiring for relay (D9 per-service state).

## Build & test
`tuist generate --no-open` (new files must be globbed in) → `make check` →
`make test DEST='platform=iOS Simulator,id=83B71AA8-A3FA-4095-9D05-226A6FE1FE75'`
(or `-only-testing:VaultifyTests/RelayPrincipalIdentityTests` etc.).
