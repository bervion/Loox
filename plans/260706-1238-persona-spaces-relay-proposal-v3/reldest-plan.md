---
title: "Relay Destination + Alias Management UX"
description: "Wire per-alias real-email destination (rotateDestination) + alias detail/write-back UX onto the live relay."
status: done
priority: P2
effort: 12h
branch: feat/relay-destination-alias-mgmt
tags: [relay, personas, aliases, email, ui]
created: 2026-07-06
---

# Relay Destination + Alias Management UX

Relay is LIVE (P0–P4B merged). Backend now forwards each alias to a per-alias REAL email
set via `rotateDestination` (kind=3, signed + vector-frozen). "Create an alias" becomes TWO
calls: `createAlias` (mint) → `rotateDestination` (set real email). This plan wires the
destination end-to-end and adds the alias-management UX.

## LOCKED product decisions (do not revisit)
1. Real email (destination) = owning persona's identity-card **Email** field (`profileItem(for:)`'s
   first `.email`). No email → block activate, guide user to add one.
2. After activation, write the alias back as a NEW field labeled **"Private email"** (`.email`):
   persona-tier → profile card (real Email kept intact, alias appended AFTER it); per-site →
   the bound LOGIN item (so it autofills on its site).
3. Destination is **per-persona**. Changing persona A's email re-rotates only A's active aliases.

## Invariants
- Local state changes ONLY after backend success (P4B). Failed activate/rotate leaves alias where it was + surfaces error.
- INV-R03: never resolve another persona's email/profile; per-site write-back targets the bound login (persona's Space).
- Sealed writes bump `updatedAt` (LWW). Files <200 LOC. New file → `tuist generate`. EN+VI localization.

## Phases (dependency order)
| # | Phase | Depends | Status |
|---|-------|---------|--------|
| 1 | [Destination plumbing + resumable activate](reldest-phase-01-destination-plumbing.md) | — | pending |
| 2 | [Write-back to profile / login](reldest-phase-02-write-back.md) | P1 | pending |
| 3 | [Change real email + rotate-all](reldest-phase-03-change-email-rotate-all.md) | P1 | pending |
| 4 | [Alias detail screen](reldest-phase-04-alias-detail-screen.md) | P1, P2, P3 | pending |
| 5 | [Aliases screen wiring + guards](reldest-phase-05-aliases-screen-wiring.md) | P1, P4 | pending |

Phases are a sequential chain (each builds on P1); file overlap between phases is fine (not parallel).

## Build / test
- `tuist generate --no-open` then `make check` (app + embedded extension compile).
- Unit: `xcodebuild test ... -only-testing:VaultifyTests/<Suite>` on booted sim 83B71AA8-A3FA-4095-9D05-226A6FE1FE75.
- Live path (createAlias→rotate, rotate-all, offline-leaves-reserved) = **device QA** — can't unit-test network.

## Success = all of
- Activate does createAlias → rotateDestination(real email) → active + `forwardingTarget`; resumable on partial failure (no orphan re-mint).
- Activated alias appears as "Private email" on the correct item (profile vs login); real email stays the AutoFill username on the profile.
- Editing "Forwards to" re-rotates that persona's active aliases; partial failure reports progress, keeps rotated ones live.
- Create blocked with a clear "add an email first" message when the persona profile has no email.
- All new copy localized EN+VI; `make check` green; pure logic unit-tested.
