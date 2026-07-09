# Root Cause — Recipient Stranded by Stale Participant Escrow (authenticationFailure)

Date: 2026-07-09. Found via on-device `ShareDiagnostics` (`###` log) on two phones (different
Apple IDs).

## Evidence

Owner A:
```
OWNER: participantAccepted=true zone=apz-… participants=[1:2,3:2]   (owner+participant = accepted)
OWNER: fetchParticipantProfile: NONE in apz-…                       (forever — B never published)
```
Recipient B:
```
RESUME: begin (flag set, unlocked)
RESUME: attempt 0..5 ERROR: authenticationFailure
RESUME: exhausted retries — flag kept
```
No `ESCROW:`/`ZONES:` lines on B — the throw happens before they log.

## Root cause

`authenticationFailure` is `CryptoKit.CryptoKitError.authenticationFailure` (a GCM tag mismatch),
NOT a CloudKit auth error. The only decryption in the resume chain is
`ParticipantIdentity.fromEscrow(envelope, vaultKey:)` (`ParticipantIdentity.swift:37`,
`AESGCM.open`).

B had a pre-existing `ApprovalParticipantEscrow` singleton in its private "Vault" zone, sealed
under a **previous** Vault Key (earlier test/onboard, then vault reset/reinstall generated a new
key; the create-if-not-exists singleton was never overwritten). `ParticipantEscrowService.ensureIdentity`:
- local cache path is `try?` → stale cache silently falls through;
- cloud path did `let identity = try ParticipantIdentity.fromEscrow(envelope, vaultKey:)` — the
  stale envelope can't open with the current key → throws `authenticationFailure`;
- because `fetchEscrowEnvelope()` returned non-nil, the transactional **create** path was never
  reached.

→ B could neither open nor recreate its identity → never published its profile → A stuck on
"accepted, finishing on their device" forever. (This is unrelated to the earlier breadcrumb-burn
fix; that fix is correct and still needed — this is a deeper, independent block.)

## Fix

`ensureIdentity` now fetches the escrow **record** (not just the envelope). If the envelope is
missing or fails to unseal with the current key, it treats the escrow as dead and **regenerates
in place** (`regenerateEscrow`): fresh identity sealed under the current key, saved over the
fetched record's change tag (collision → adopt-or-retry). A dead escrow's identity was never
usable and any owner pin on it was already broken, so overwriting only recovers B for future
shares.

## Recovery for the currently-stuck device

The fix self-heals on next resume/foreground: B regenerates, publishes, A advances to the
fingerprint ceremony. No manual step.

## Verification
- Compile passes (app + extension). Full unit suite green.
- New `ParticipantEscrowStaleKeyTests`: same-key roundtrip recovers; wrong key throws
  `CryptoKitError` (the exact stranding failure); corrupt version byte throws.
- Device QA: rebuild both phones, retry the share — B's log should show `ESCROW: cloud escrow
  UNSEALABLE — regenerating` then `PUBLISH: profile published`, and A `fetchParticipantProfile:
  FOUND`.

## Unresolved
- Multi-device recipient with NO vault-key sync (each device a different Vault Key) could
  ping-pong regenerating the escrow. Out of scope for the reported 2-device/different-account
  case; the escrow model already assumes B's devices share the Vault Key via escrow sync.
- Consider re-sealing the participant escrow on any future Vault-Key rotation path so it never
  goes stale in the first place.
