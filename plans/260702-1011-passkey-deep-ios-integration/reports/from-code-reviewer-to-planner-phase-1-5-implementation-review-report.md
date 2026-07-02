# Code Review — Passkey Deep iOS Integration, Phases 1–5

Branch `codex/passkey-deep-ios-integration` vs `main`. Reviewed 2026-07-02. Reviewer self-ran gates (subagent quota blocked).

## Verdict: SHIP-READY (core). No blocking issues.

Independently verified:
- `make check` (app + extension) → exit 0.
- Full `VaultifyTests` → **114 tests, 0 failures, TEST SUCCEEDED** (ran with concrete sim UDID; `name=iPhone 16` does NOT resolve here — use `id=<UDID>`).
- Localization EN+VI: **complete** for every new string (ceremony, Passkeys screen, detail sheet, settings toggle+footer, import/export, quarantine banner). No missing VI.
- `ic_passkey` asset present; design tokens (`iconInline/iconUtility/iconTileLarge`) exist.

## Red-team findings compliance (all 15 verified applied)

- RT-1 (no password-change coupling): confirmed — no hook; Vault Key immutability respected. `PasskeyEnvelope` invalidates only on erase (bundle wipe).
- RT-2 (verify, don't trust): `provisionOrVerify` unseals private key w/ current Vault Key, derives+compares public, quarantines on mismatch, queues D7 notice. Untrusted-input validation on `open` (version byte, size cap, secret sanity, P256 key parse).
- RT-3 (store injection): `PasskeyVault` is `struct { let store }`; no internal container construction; tests use in-memory store (`TestLifetimeRetainer`).
- RT-4 (crypto/API pin): `HPKE.Ciphersuite.Curve25519_SHA256_ChachaPoly` + 1-byte version; override is `performWithoutUserInteractionIfPossible(passkeyRegistration:)`.
- RT-6 (atomic dedupe): `save` deletes replaced + inserts in one `context.save()`; returns replaced SECRETS.
- RT-7 (identity race): `CredentialIdentityRefreshGate` — generation stamp + serialized tail Task; stale snapshots aborted after each await.
- RT-8 (reads never write): `all/matching/secret` open both forms read-only; migration+dedupe only in `prepareEnvelopeOnUnlock` (app `reload()` + extension `PasskeyMigrationGate`).
- RT-10 (await identity before complete): interactive + silent paths `await` save/remove before `complete*Request`; silent path also rolls back on failure.
- RT-11 (metadata-only cache): `VaultRepository.passkeys: [PasskeyInfo]` — no `privateKeyRaw`; signing re-fetches secret in the extension only.
- RT-14 (per-credential flags): `PasskeySecret.flags`; new = UP|UV|BE|BS(|AT), legacy nil → UP|UV.
- RT-15 (marker-only logs): silent path logs "performed"/"skipped(reason)" with generic reason codes; never rp/userName.
- RT-5/9/12/13 (structure/paths): envelope keys as `VaultKeyBundle` optional fields; xcstrings path correct; `VaultItem.matchesRelyingParty` reuses convention; gates split VC(pre-unlock)/view(post-unlock).

## Decisions D4–D7 verified

- D4 flags: as above. D5 auto-upgrade default ON (`SharedConfig.automaticPasskeyUpgradesEnabled` defaults true). D6 backup: `EncryptedBackup` payload gains optional `passkeys`; legacy decode fallback + import validation; CSV excluded. D7 quarantine: sites persisted, one-time banner in `PasskeysScreen` with Dismiss.

## Non-blocking observations (no code change required)

1. Quarantine banner snapshots `SharedConfig.quarantinedPasskeySites` at `@State` init — won't live-update if a quarantine lands while the screen is already open. Rare; refreshes on next entry. Acceptable.
2. App↔extension concurrent SwiftData writes (silent reg while app foregrounded) — pre-existing contention class; silent path catches + rolls back. Documented residual.
3. Envelope public-key substitution / record poisoning — documented residual (RT-2); mitigated by verify-on-unlock + quarantine notice; no backup-exclusion (legitimate restores must work).

## Must-do before TestFlight (unchanged from plan; CANNOT be sim/unit-verified)

- Manual device QA: Face ID sheet in passkey ceremonies; QuickType passkey suggestion appears after unlock + after in-extension registration; suggestion disappears after delete; real iOS 18 automatic-upgrade trigger on an RP (time-boxed — "no upgrade offered" is non-bug).

## Unresolved questions

- None technical. Direction only: at the user-set post-Phase-5 checkpoint (release vs stretch phases 6–7).
