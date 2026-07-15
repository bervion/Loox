# Family full-group sharing + Devices key-rotation revoke — execution plan

Status: **Planned, execution-ready.** Two security-critical crypto/transport projects that finish the Profile refactor's deferred features. Neither is verifiable headlessly (2-account / 2-device flows), so each ships **phase-by-phase behind a flag, gated on a device/account test matrix** — the F2 red-team (PR #106) proved a blind one-shot produces architecturally wrong crypto.

Grounding: `plans/260715-1630-profile-refactor/design-family-group.md` + `design-devices-revoke.md` + the crypto scouts in this session.

## The two projects
| # | Project | Detailed plan | Core change | Can I verify? |
|---|---------|---------------|-------------|---------------|
| A | **Family full-group** (share a Space to members, manage, revoke) | `family-group-transport.md` | Namespace grant/display/field records **per `grant.id` within a zone** so N logins share in one ceremony; capability safelist; one-ceremony fan-out UI | Compile + unit; **end-to-end needs 2 iCloud accounts** |
| B | **Devices revoke** (real key rotation) | `devices-key-rotation.md` | Rotate the 32-byte Vault Key: re-seal every record (dual-key window + resumable journal), re-wrap KEKs, re-provision kept devices, regenerate Emergency Kit | Local re-seal is **unit-testable**; **multi-device + crash paths need 2 devices** |

## Execution model (the "best" way for unverifiable crypto)
Each project runs as ordered phases. **Every phase that touches the transport or the key ships behind a compile/runtime flag, with a written test checklist you run before the flag flips on.** I implement a phase → `make check` + unit tests → you run its device/account checklist → I fix from your logs → next phase. No phase merges to the default path until its checklist passes.

- Order: **B-phase-1 first** (local re-seal engine + KATs — the one large chunk I *can* unit-test), then A (needs your 2 accounts throughout), then B's multi-device phases (need your 2 devices).
- Everything stays **additive + flagged** so `main` is never destabilized; the existing per-item sharing and single-key vault keep working untouched until a phase's checklist passes.

## Cross-cutting invariants (must hold every phase)
- **Vault Key never syncs** (B must not weaken it — re-provision is via pairing/escrow, not a synced key).
- **Persona isolation INV-R03** (A only shares the active persona's Space items — already verified safe).
- **Hand-over is irreversible INV-08** (A safelists login fields; never blanket-shares notes/2FA/passkeys).
- **No data loss** (B: dual-key read window + resumable journal + kept-device adoption before old-key/escrow teardown).
- Localized EN+VI; design-system tokens; `make check` green each phase.

## Definition of done
- A: an owner shares a Space to a member in one ceremony; the recipient projects **all** logins; owner can revoke the member; two-account test matrix passes; `/ak:security` review clean.
- B: an owner rotates the key from Devices → a revoked device can no longer decrypt future ciphertext; kept devices re-adopt without data loss; crash/offline matrix passes; Emergency Kit regenerated; `/ak:security` review clean.

## Risks / honesty
- Both are large and touch the crown-jewel crypto. Estimated multi-session even with the loop.
- I cannot sign off correctness without your device/account testing between phases — that gate is the plan, not an afterthought.
