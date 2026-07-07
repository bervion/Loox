# Phase A — Relay App Attest Assertion (iOS)

**Priority:** P0 · **Status:** Ready (no BE dependency) · **Target:** unblock BE relay `ASSERTION_MODE off→shadow→required`.

**Context:** BE relay App Attest is fully built and gated at `ASSERTION_MODE=off`; iOS is the missing half. This phase ships the client register + per-command assertion + parity freeze so BE can flip to shadow then required.

---

## Key insights (verified in code)

- Assertion is **challenge-free per command**: `clientDataHash = SHA256(relayCommandTranscript(command))` (`command-assertion.ts:46`). The relay challenge is consumed **only at register**. Freshness for mutations = existing nonce single-use + `sign_count` CAS. → No per-command challenge plumbing.
- App Attest key is device-level & backend-agnostic, but **registration is per-backend** — loox-relay trusts only keys in its own `attest_keys`. Relay needs its own register call + its own registered-flag.
- The assertion gate covers **all** relay control mutations (`control-handlers.ts:127-135`), so send the assertion on every mutation (createAlias…rotatePrincipal). Sending `X-Loox-App-Attest-Key-Id` also feeds the `device` rate dimension — useful signal even in shadow.
- `RelayAPIClient` is principal-sig-only today (sig in JSON body); header hooks are net-new.

## Frozen BE contract (build to this exactly)

- **Challenge:** `POST /v1/relay/attestation/challenges` → `{challengeId, challenge}` (base64url, single-use, 180s TTL).
- **Register:** `POST /v1/relay/attestation/register` — headers `X-Loox-Challenge-Id`, `X-Loox-App-Attest-Key-Id` (base64 keyId); body `{"attestation_object_b64": "<string>"}`; register `clientDataHash = SHA256(rawChallengeBytes)` (decode base64url first). → **204**; errors: `bad_request` 400, `challenge_invalid` 401, `key_id_mismatch` 400, `attestation_failed` 400.
- **Assertion (per mutation):** headers `X-Loox-App-Attest-Key-Id` + `X-Loox-App-Attest-Assertion`; `clientDataHash = SHA256(canonical LOOX-RELAY-AUTHZ-V1 command bytes)`. BE advances `sign_count` CAS (`counter_replay`).

## Architecture

New app-target module `RelayAttestation` (mirrors `LooxLinkAttestation`, **do not** put in `VaultifyCore` — keep DeviceCheck out of the appex; relay isn't called from the extension). Reuses `DCAppAttestService`; relay-namespaced keychain accounts + own registered-flag. Reuses the existing frozen command encoder (`VaultifyCore/Relay/RelayCommandCanonical.swift`) for the assertion `clientDataHash`. Decision: relay uses its **own** keyId (isolation, no refactor of shipped loox-link code); optional later consolidation to a shared key provider (noted risk).

## Related files

**Create:**
- `Vaultify/Services/Relay/RelayAttestation.swift` — key load/generate, register, assert(commandBytes) → (keyId, assertionB64).

**Modify:**
- `Vaultify/Services/Relay/RelayAPIClient.swift` — add relay attest challenge + register calls; accept optional `(keyId, assertion)` on `send(...)` → set `X-Loox-App-Attest-Key-Id` / `-Assertion` headers (near `:48-52`). Remove the "do not send assertion headers" prohibition comment (`:3-6`).
- `Vaultify/Services/Relay/RelayService.swift` — after signing command, if attestation enabled: `RelayAttestation.assert(canonicalBytes)` → pass keyId+assertion to `RelayAPIClient.send` (`:196-201`).
- `VaultifyCore/Relay/RelayConfig.swift` (or new `RelayFeature`) — `attestationEnabled` (shadow) + `attestationRequired` (lockstep) flags, relay attest endpoints.
- `Vaultify/Services/Relay/RelayRetryPolicy.swift` — classify assertion failures (registration vs assertion vs counter_replay) into existing taxonomy.
- `VaultifyTests/Fixtures/relay-authz-command-vectors-v1.json` + a test — add/assert `client_data_hash = SHA256(canonicalBytes)` per vector (the parity freeze BE waits on).

## Implementation steps

1. **`RelayAttestation`**: `keyId` provider (load relay-namespaced keychain account, else `generateKey()`); `register()` — skip if registered-flag set; else fetch relay challenge → `attestKey(keyId, SHA256(rawChallengeBytes))` → POST register (challengeId + keyId headers + `attestation_object_b64`) → on 204 set flag. One retry on `DCError.invalidKey` → `resetKey()` (new keyId) + re-register.
2. **`assert(commandBytes)`**: ensure registered → `clientDataHash = SHA256(commandBytes)` → `generateAssertion(keyId, clientDataHash)` → return `(keyId, assertionB64)`. Fail-soft when `attestationEnabled` shadow: return nil, never throw to block the mutation.
3. **Thread headers**: extend `RelayAPIClient.send` signature with optional `attest: (keyId, assertion)?`; set the two `X-Loox-*` headers when present (keep principal sig in body as-is).
4. **Wire `RelayService.send`**: build+sign command → canonical bytes (already computed for signing) → if `attestationEnabled` call `RelayAttestation.assert(bytes)` → pass to API client. Applies to all kinds (1..6).
5. **Flags**: `attestationEnabled=true` (shadow) once register happy-path verified; `attestationRequired` stays false until BE `ASSERTION_MODE=required` (flip together).
6. **Parity freeze**: for each frozen command vector, assert iOS `SHA256(canonicalBytes) == client_data_hash`; hand the fixture to BE to confirm identical (this is the "parity fixture" gating shadow→required).
7. **Device QA**: real device — register **204**, one shadow mutation with assertion accepted by BE log (`[relay-assertion-shadow] ok`), Core Vault + relay mutation unaffected on assertion failure.

## Todo

- [ ] `RelayAttestation.swift` (key/register/assert, fail-soft, one-retry)
- [ ] Relay attest challenge + register in `RelayAPIClient`
- [ ] Header threading `RelayService.send` → `RelayAPIClient.send`
- [ ] `attestationEnabled`/`attestationRequired` flags
- [ ] Assertion-failure classification in retry policy
- [ ] `client_data_hash` parity vector + test
- [ ] Compile check (`make check`), unit tests green
- [ ] Real-device happy-path QA
- [ ] Hand parity fixture to BE → BE flips `off→shadow`

## Success criteria

1. Relay App Attest key registers with loox-relay (**204**), relay-namespaced flag persisted.
2. All relay control mutations carry `X-Loox-App-Attest-Key-Id` + `-Assertion` when `attestationEnabled`.
3. iOS `SHA256(canonicalBytes)` == BE `clientDataHash` for every frozen vector.
4. Shadow: assertion absent/failed never blocks a mutation (principal sig remains live auth); Core Vault untouched.
5. Device happy-path validated; BE observes `[relay-assertion-shadow] ok`.
6. Lockstep flag ready so BE can move to `required` with a client build flip.

## Security / edge cases

- Fail-closed only when `attestationRequired`; fail-soft in shadow (INV-API-07: App Attest failure must not break Core Vault).
- Reinstall/restore → `DCError.invalidKey` → reset key + re-register (one retry), same as loox-link.
- Do not send assertion headers for read/GET paths (none exist on relay control today).
- Extension: no relay App Attest (relay not called there).

## Open questions
None blocking. BE-side flip to `required` waits on the parity fixture handoff (step 6) + device QA.
