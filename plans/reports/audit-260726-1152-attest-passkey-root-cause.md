# Root-cause report — App Attest "couldn't prove genuine install" + passkeys lost/never syncing

**Date:** 2026-07-26 · **Scope:** read-only audit, no files changed
**Repos:** `/Users/bervion/Developer/Projects/mobile/ios/Vaultify`, `/Users/bervion/Developer/Projects/frontend/looxpassword`

---

## 1. Verdict

**Issue 1 — "This app couldn't prove it's a genuine Loox install."**
Root cause: **the App Attest key id and its "already registered" marker are persisted in the Keychain under account names that do not encode the backend environment, while `#if DEBUG` repoints Share Link and Quick View at a *different backend with a different attested-key database*.** `LooxLinkAttestation.swift:16,25` store `loox-link-app-attest-key-id` / `loox-link-app-attest-registered`; `QuickViewAttestation.swift:19,39` store the quick-view twins. `LooxLinkConfig.swift:10-16` and `QuickViewConfig.swift:10-14` send DEBUG to `api-staging.looxpassword.com` and Release to `api.looxpassword.com`. Those are separate Workers over separate D1s (`workers/loox-link/wrangler.jsonc:46` staging `4f4d46a9-…` vs `:65` production `19e149a2-…`). A Debug run registers key K into the staging DB and sets the marker; the Release/TestFlight build installed **over the top** reads the marker, skips `register()` (`LooxLinkAttestation.swift:101`), asserts K against production, and production answers `key_unknown` (`workers/loox-link/src/app-attest/create-assertion.ts:78-81`) → `json({error:'unauthorized'}, 401)` (`src/index.ts:112`) → `LooxLinkAPIError.unauthorized` (`LooxLinkAPIClient.swift:201` → `:18`) → the exact reported string. It never self-heals in place, because the only reset trigger is `catch let error as DCError where error.code == .invalidKey` (`LooxLinkAttestation.swift:38`) and the Secure Enclave key is perfectly valid locally. A second, independent defect amplifies it: `LooxLinkConfig.attestationRequired = false` (`:31`) while **both** loox-link Workers run `ASSERTION_MODE=required` — so *any* attest failure is swallowed at `LooxLinkService.swift:77-82` and a header-less create is posted, which 401s with the same message. Relay is unaffected only because `RelayConfig.swift:15` is hardcoded to production in both configurations — which is exactly why Private Email still works while Share Link and Quick View both broke.

**Issue 2 — passkeys not restored, never synced.**
Root cause: **the CloudKit record type `VaultPasskey` was almost certainly never deployed to the Production schema.** This is a *plain unfinished ops step*, not a design limitation and not a code bug. The passkey private key is a plain software P-256 key (`PasskeyModels.swift:12 privateKeyRaw: Data`), fully exportable, and it is carried correctly by the encrypted file backup (`VaultBackup.swift:107-124`, `:130-153`). But "restore from the kit" is a *CloudKit* restore: the recovery key only unwraps the escrow envelope (`JoinVaultFlow.swift:572`), then `completeJoin` turns sync on and pulls everything (`JoinVaultFlow.swift:122`). Passkeys ride their own plane `VaultPasskey` (`CloudSyncService.swift:25`), pushed at `:111`/`:265-288`. CloudKit Production has no just-in-time schema creation, so an undeployed type makes every push fail; `dirty` never clears (`markPasskeySynced` is only called inside `if case .success`, `CloudSyncService.swift:281-288`), nothing ever lands in the zone, and the pull at `:174` receives zero passkey records. The repo's own plan still flags this as an open blocking gate: `plans/260717-1040-passkey-cloudkit-sync/plan.md:3` ("PENDING: CloudKit Production deploy of `VaultPasskey` (OPS gate)") and `:30`. The plane shipped anyway in v1.36.0. **No code change fixes this — it is a Console deploy.**

**Your `LOOX_CAP_SIGNING_KEY_PKCS8_B64` hypothesis is dead.** Ruled out below with live output.

---

## 2. Issue 1 — App Attest

### 2.1 Why the config-signing key is ruled out

```
$ curl -s https://config.looxpassword.com/v1/capabilities
{"schema_version":2,"manifest_version":8,"key_id":"cap-2026-02",
 "issued_at":1783525383826,"expires_at":1786117383826, ...}
```
`issued_at` = 2026-07-08, `expires_at` = 2026-08-07 — live and unexpired today (2026-07-26). The app's only bundled trusted key is `cap-2026-02` (`VaultifyCore/Models/CapabilityManifest.swift:160-163`). Key ids match, nothing is expired, and — decisively — **the capability manifest is not on the failing code path at all**. A capability failure raises `LooxLinkAPIError.capability(...)` whose copy is "Share Links are temporarily unavailable…" (`LooxLinkAPIClient.swift:21-23`). The string you saw comes only from `.unauthorized` (`LooxLinkAPIClient.swift:18`, `QuickViewAPIClient.swift:19`) — an HTTP 401 from the App Attest gate. `LOOX_CAP_SIGNING_KEY_PKCS8_B64` cannot produce it.

### 2.2 Production really is in `required` mode (proven, not assumed)

A bare 401 proves nothing (off/shadow with `APP_CREATE_TOKEN` returns the same). The `invalid_json` branch exists **only** inside `if (mode === 'required')` (`workers/loox-link/src/index.ts:100-107`):

```
$ curl -s -X POST https://api.looxpassword.com/v1/shares -H 'Content-Type: application/json' --data 'not-json'
{"error":"invalid_json"}   # 400

$ curl -s -X POST https://api.looxpassword.com/v1/shares -H 'Content-Type: application/json' \
    --data '{"ciphertext":"AA","iv":"AA","expires_in_seconds":300}'
{"error":"unauthorized"}   # 401
```
Production loox-link is `ASSERTION_MODE=required`, deployed. Confirmed in config too: `workers/loox-link/wrangler.jsonc:50` (staging) and `:67` (production) both `"ASSERTION_MODE": "required"`. Quick View: staging `"off"` (`workers/loox-quick-view/wrangler.jsonc:36,69`), production `"required"` (`:99`).

### 2.3 Causal chain

1. `LooxLinkConfig.swift:10-16` — DEBUG → `api-staging.looxpassword.com`, Release → `api.looxpassword.com`. Same split at `QuickViewConfig.swift:10-14`.
2. `LooxLinkAttestation.swift:16` / `:25` — Keychain accounts `loox-link-app-attest-key-id`, `loox-link-app-attest-registered`. No host, no env. Same at `QuickViewAttestation.swift:19,39`.
3. `VaultifyCore/Keychain/KeychainStore.swift:12` — one fixed service `com.bervion.vaultify`, account verbatim. `Project.swift:55` uses one bundle id for every configuration (only `APS_ENVIRONMENT` differs, `Project.swift:45-46`). Debug, local Release and TestFlight share the identical Keychain scope.
4. `LooxLinkAttestation.swift:101` — `if (try? KeychainStore.get(account: registeredAccount)) == nil { register(...) }`. The marker is `Data([1])` (`:111`) — it describes *nothing*, so it authorizes any key against any backend.
5. `workers/loox-link/src/app-attest/create-assertion.ts:78-81` — `if (!keyRow || keyRow.state !== 'REGISTERED' || keyRow.env !== environment) return {ok:false, error:'key_unknown'}`. `getAttestedKey` reads only the Worker's own D1 binding, so a staging-registered key is simply **absent**; the `!keyRow` branch fires (the `env` clause is dead belt-and-braces because the DBs are already per-env).
6. `workers/loox-link/src/index.ts:111-113` — `if (!verdict.ok) return json({error:'unauthorized'}, 401)`, with **no logging of `verdict.error`** in the required branch.
7. `LooxLinkAPIClient.swift:201` → `.unauthorized` → `:18` → the user-facing string.
8. No recovery: `resetKey()` (`LooxLinkAttestation.swift:129`) is called only from the two `DCError.invalidKey` catches (`:38`, `:71`) and from a `register()` throw (`:107`) — and `register()` is never reached because the marker is set. An HTTP 401 is not a `DCError`. `AppEnvironment.eraseEverything()` (`:329-364`) clears relay/escrow/approval caches and never touches these four accounts.

### 2.4 Live D1 evidence

```
$ npx wrangler d1 execute loox-link-production --remote --env production \
    --command "SELECT key_id, sign_count, datetime(created_at,'unixepoch'), datetime(updated_at,'unixepoch') FROM attest_keys"
QxcIxONF…  sc=3  created 2026-07-07 12:27:03  used 2026-07-07 16:15:06
/ttx7HC+…  sc=1  created 2026-07-08 16:09:43  used 2026-07-08 16:09:44
g7k/KfrJ…  sc=3  created 2026-07-10 21:16:20  used 2026-07-11 17:32:11

$ … loox-link-staging   → P06Lvu/T…  sc=21  created 2026-07-06 04:31:38  used 2026-07-11 16:02:34
$ … loox-quick-view-production → iAoEu10A… sc=2 (07-08 16:36), jVPx+UKU… sc=2 (07-08 16:40)
$ … loox-quick-view-staging    → 0 rows
```
Read this carefully:
- **Zero App Attest activity in any production Worker since 2026-07-11 17:32**, across v1.37 → v1.39. A `key_unknown` assertion writes nothing, so this is exactly the fingerprint of "device keeps asserting a key production has never seen".
- **`loox-quick-view-staging` has never had a single key**, even though DEBUG builds point Quick View at staging. That is only possible if the `quick-view-app-attest-registered` marker was already set by a *production* run and the DEBUG build therefore skipped register — the same bug, running in the other direction, invisible because QV staging is `ASSERTION_MODE=off`.
- `attest_challenges`, `shares`, `short_links`, `rate_counters` in production are all empty; that is **not** evidence of no traffic — a `*/2 * * * *` cron purges expired rows (`workers/loox-link/wrangler.jsonc:35,54`; `src/attest-challenge.ts:254`). Do not read those tables as usage counters.

### 2.5 Why Debug works, local Release and TestFlight do not

The App Attest *Apple* environment follows the signing profile, not the build configuration: dev-signed (Debug **and** local Release) = sandbox, TestFlight = production. There is no `com.apple.developer.devicecheck.appattest-environment` anywhere (`Vaultify/Vaultify.entitlements` verified in full; `grep -niE "appattest|devicecheck" Project.swift` → no match) — and on iOS that entitlement is macOS-only anyway, so this is a platform property, not a repo defect.

- **Local Release over a Debug install** — same sandbox key, so no `invalidKey`; the stale staging key is asserted against production → permanent 401. ✅ matches report.
- **TestFlight *update* over an existing install** — the install (and its App Attest key) is preserved. If the stored key was staging-registered and the Apple environment did not change for that key, the same permanent 401 applies. ✅ matches report.
- **Delete the app, then install** — the App Attest key dies with the app; `generateAssertion` throws `DCError.invalidKey`, `resetKey()` fires, a fresh key registers against production and it works. This is your immediate manual workaround, and it is also the falsifiable test in §5.

### 2.6 The second, independent defect (fix it in the same PR or the fix will look like it failed)

`LooxLinkConfig.swift:31` — `attestationRequired = false`, with a comment claiming the server is in shadow (`:19-30`). Both Workers have been `required` since 2026-07-07. `LooxLinkService.swift:77-82` therefore swallows every attest error and calls `api.createShare(..., assertion: nil)`, which required-mode answers 401 — same string, zero diagnostics, and the `register()`-failure catch at `LooxLinkAttestation.swift:104-110` has already burned an App Attest key (a key can be attested with Apple exactly once). Corollary: the whole `LooxLinkAppToken` / `TUIST_LOOX_LINK_PROD_TOKEN` plumbing is dead in production — `index.ts:116-120` only reads `APP_CREATE_TOKEN` in the `off`/`shadow` branch. Do not chase a missing token.

Also note: Quick View's *upload* failure never renders this string. `QuickViewApprovalFlowModel.swift:244-250` rewrites every non-cancel error to `genericErrorMessage` = "Start again on the computer." (`:74`). If you literally saw the "genuine Loox install" wording on the Quick View surface, it came from a different Quick View call site or from Share Link — worth pinning down (§5, Q3).

### 2.7 The fix

**iOS — required, this is the actual fix.**

`Vaultify/Features/Sharing/LooxLink/LooxLinkAttestation.swift`
```swift
// replace lines 16 and 25
private static var envTag: String { LooxLinkConfig.apiBase.host ?? "unknown" }
private static var keyIdAccount: String { "loox-link-app-attest-key-id.\(envTag)" }
private static var registeredAccount: String { "loox-link-app-attest-registered.\(envTag)" }
```
Deriving from `apiBase.host` (not `#if DEBUG`) also covers the DEBUG `loox_link_api_base_url` override at `LooxLinkConfig.swift:60-64`.

`Vaultify/Features/Sharing/QuickView/QuickViewAttestation.swift` — same shape, from `QuickViewConfig.apiBase.host` (lines 19, 39).

Then, in `registeredKeyId` (`LooxLinkAttestation.swift:101`, `QuickViewAttestation.swift:120`), write the marker as the keyId itself, not `Data([1])`, and require it to equal the stored keyId before skipping register. A marker that cannot describe the key it authorizes is how this bug survived.

Add self-heal: in `LooxLinkService.createLink` / `createShortLink` and `QuickViewApprovalFlowModel.upload`, catch `.unauthorized` **once**, call a new `invalidateRegistration()` (delete both accounts — a key that failed a server check may already be burned, so drop the key too), and retry the whole assert+request once. Budget exactly one retry, mirroring the existing `invalidKey` budget.

Flip `LooxLinkConfig.attestationRequired = true` (`:31`) and rewrite its comment plus `LooxLinkService.swift:65-70`; replace the `#if DEBUG print` at `LooxLinkService.swift:79-81` with an OSLog `.public` line copying `QuickViewAttestation.describe` (`QuickViewAttestation.swift:26-30`).

Optional hygiene: add the four accounts to `AppEnvironment.eraseEverything()` (`:329-364`).

**Backend — optional, diagnostics only. Not required to fix the bug.**
`workers/loox-link/src/index.ts:112`:
```diff
         const verdict = await verifyCreateAssertion(req, env, toAssertionBody(parsed));
-        if (!verdict.ok) return json({error: 'unauthorized'}, 401);
+        if (!verdict.ok) {
+          console.log('[assertion-required]', `fail:${verdict.error}`);
+          return json({error: 'unauthorized'}, 401);
+        }
```
(mirrors what quick-view already does at `workers/loox-quick-view/src/payload-upload.ts:117`). Deploy:
```bash
cd /Users/bervion/Developer/Projects/frontend/looxpassword/workers/loox-link
npx wrangler deploy --env production
```

---

## 3. Issue 2 — passkeys

### 3.1 It is NOT a design limitation. Bluntly.

Vaultify passkeys are **software** P-256 keys. `PasskeySecret` (`VaultifyCore/Passkey/PasskeyModels.swift:7-30`) holds `privateKeyRaw: Data` — the raw 32 bytes — with no custom `CodingKeys`, no Secure Enclave, no `SecAccessControl`, no non-extractable attribute anywhere in `VaultifyCore/Passkey/`. `PasskeyVault.seal()` JSON-encodes it and AES-256-GCM-seals it under the Vault Key into `PasskeyRecord.sealed`. Everything except `usedAt` is portable by construction. There is nothing here that a correct sync could not carry.

The **file** backup already carries them correctly and is test-covered: `VaultBackup.exportEncrypted` (`Vaultify/Services/ImportExport/VaultBackup.swift:107-124`) writes `passkeys: [PasskeySecret]` into the sealed payload; `importEncryptedWithPasskeys` (`:130-153`) decodes them with a **throwing** map (no silent `try?`); `ExportView.swift:109-117` hard-fails with `ExportError.passkeysUnavailable` rather than writing a lossy file; `VaultifyTests/PasskeyBackupRoundtripTests.swift` asserts `privateKeyRaw` and `flags` round-trip. **No field is dropped in any encoder or mapping.**

### 3.2 Causal chain (the CloudKit plane)

1. `VaultifyCore/Store/VaultStore.swift:33-38` — one SwiftData container, `cloudKitDatabase: .none`. Nothing in `Vault.store` crosses devices by itself; every record class needs its own CloudSync plane.
2. Recovery-key restore is a CloudKit restore: `JoinVaultFlow.swift:572` fetches the escrow envelope, `VaultSession.unwrap` adopts the key, `completeJoin` (`:111-131`) sets `env.settings.iCloudSyncEnabled = true` and calls `env.syncNow()`. All content arrives via `pull()`.
3. `CloudSyncService.swift:25` — `passkeyRecordType = "VaultPasskey"`. Pushed at `:111` inside the fault-isolated `push()` (`:100-118`), mapped at `:291-307`, pulled at `:174`.
4. `pushPasskeys()` (`:265-288`) filters `dirty && envelopeSealed == nil && id.utf8.count <= 255`. Vaultify credential ids are 22 chars, so the length guard is inert; the envelope guard only defers iOS-18 locked-write staging. `PasskeyRecord.dirty` defaults `true` (`PasskeyModels.swift:98`, and `:117` in `init`), so every pre-existing passkey is queued. **The client side is correct end to end.**
5. `markPasskeySynced` is called only inside `if case .success` (`CloudSyncService.swift:281-285`). A server rejection therefore leaves `dirty = true` forever and nothing reaches the zone. Line **`CloudSyncService.swift:280`** is the exact point of loss.
6. The rejection is a Production schema miss. `plans/260717-1040-passkey-cloudkit-sync/plan.md:3` — *"PENDING: CloudKit Production deploy of `VaultPasskey` (OPS gate)"*. `:30` — *"`VaultPasskey` must exist in the Production CloudKit schema BEFORE any TestFlight build with phase 2 ships (Production has no just-in-time schema creation; the plane would error — isolated since the audit fix, but never syncing)."* `phase-02-cloud-sync-plane.md:10-14` is a manual Console procedure; the phase-3 two-device checklist is still `☐`. The code shipped in v1.36.0 (`CHANGELOG.md`, 2026-07-17). `git log 8e36041d..HEAD -- plans/260717-1040-passkey-cloudkit-sync/` shows the status was never updated, `docs/deployment-guide.md` has no CloudKit schema step, and there is no `cktool`/CI automation anywhere in the repo.
7. Environment note that matters for repro: there is **no** `com.apple.developer.icloud-container-environment` in `Vaultify/Vaultify.entitlements` (read in full), so the CloudKit environment follows the provisioning profile. A local Release build signed with a development profile still talks to CloudKit **Development**, where JIT schema creation is on and passkeys sync fine. **This defect is TestFlight/App-Store-only. Do not try to reproduce it with a local Release build, and do not read "it works in Release from Xcode" as a refutation.**

### 3.3 Confidence and the one check that settles it

I could not read the Production schema — `xcrun cktool get-teams` fails with *"No management token found"*, and there is no exported schema in either repo. Everything in the repo is consistent with the type being absent, and the repo's own OPS gate predicted this exact symptom, but it remains an inference until you look at the Console (§5, Q1). The alternative shape — type deployed but a field type mismatch — produces identical local behaviour.

Blast radius correction, in your favour: **nothing is lost.** Because `markPasskeySynced` never runs on a rejected save, `dirty` stays `true`; the moment the type is deployed, the next sync uploads every existing passkey. No migration, no code change, no data recovery.

Two caveats:
- The same Console session is pending for `VaultPersona`, `VaultEmailAlias`, `VaultForwardingInbox`, `AuditReport`, `AuditFindingState` (`plan.md:30`). `push()` returns only the **first** error (`:107-118`, order: items, folders, **passkeys**, personas, aliases, inboxes, audit, findings), so the passkey failure masks the five behind it. Deploy the whole set.
- The Settings status may look healthy. CloudKit's async `modifyRecords` decomposes `CKError.partialFailure` into per-record `Result`s rather than throwing; `pushPasskeys` inspects only `.success`, so per-record rejections never reach `firstError`, `sync()` sets `.success(.now)` (`:75`), and Settings → iCloud Sync reads green while passkeys silently never upload. If instead the operation fails atomically, the per-plane catch fires and Settings shows a CloudKit error. **Either way the passkeys are lost; the status string is only a discriminator, not a refutation.**

---

## 4. Ordered fix plan

| # | File / action | Change | Risk | Verification |
|---|---|---|---|---|
| 1 | **CloudKit Console** — container `iCloud.com.bervion.vaultify` | Development schema: confirm/create `VaultPasskey` with `sealed` (Bytes), `largeBlobSealed` (Bytes), `createdAt` (Date/Time), `updatedAt` (Date/Time), `deletedAtMs` (Int64). Then **Deploy Schema Changes → Production**. Do `VaultPersona`, `VaultEmailAlias`, `VaultForwardingInbox`, `AuditReport`, `AuditFindingState` in the same session. | Low — additive, no queryable index needed (zone-delta fetch only). Deploy-to-Production is all-or-nothing, so JIT-create the type with one Debug run first if it is missing from Development. | Two TestFlight devices: create a passkey on A, foreground B, passkey appears. Then delete-app → reinstall → restore by recovery key → passkeys present and AutoFill signs in. This is `phase-03-restore-verification-ui.md`'s checklist. |
| 2 | `Vaultify/Features/Sharing/LooxLink/LooxLinkAttestation.swift:16,25`<br>`Vaultify/Features/Sharing/QuickView/QuickViewAttestation.swift:19,39` | Suffix both accounts with `apiBase.host`. Store the registered marker as the keyId and require equality before skipping `register()`. | Low. Every device re-mints and re-registers once (a fresh Apple key + one `attestKey`). Watch Apple's per-device `generateKey` rate limit if you ship repeatedly. `LooxEntitlementCoordinator.swift:203,207` binds `storedKeyId`, but `ENTITLEMENT_MODE=off` in both production Workers, so re-minting is safe **today** — re-check before that flips. | Local Release build over an existing Debug install: Share Link succeeds. New rows appear in `loox-link-production.attest_keys` / `loox-quick-view-production.attest_keys`. |
| 3 | `Vaultify/Features/Sharing/LooxLink/LooxLinkConfig.swift:31` + comment `:19-30`; `LooxLinkService.swift:65-70,77-82` | `attestationRequired = true`; replace the swallow with a throw; replace the `#if DEBUG print` (`:79-81`) with OSLog `.public`. | Medium — this makes attest failures visible instead of a 401. That is the point: the outcome was already failure. | An induced attest failure now surfaces the real `DCError` in Console.app on a TestFlight build instead of "genuine Loox install". |
| 4 | `LooxLinkService.createLink` / `createShortLink`; `QuickViewApprovalFlowModel.upload` (`:206-231`) | On `.unauthorized`, call `invalidateRegistration()` (drop key + marker) and retry once. Budget one retry. | Low, if strictly one retry — an unbudgeted loop burns one Apple key per attempt. | Manually poison the Keychain account with a bogus keyId; the next share succeeds on the second attempt. |
| 5 | `workers/loox-link/src/index.ts:112` | Log `verdict.error` before the 401 (diff in §2.7). `npx wrangler deploy --env production`. | Very low, log-only. | `npx wrangler tail loox-link-production --format pretty` prints `fail:key_unknown` while reproducing. |
| 6 | `docs/deployment-guide.md` + CI | Add a CloudKit schema-deploy gate, and the check the 260717 audit already proposed: grep new `recordType` string literals against a checked-in production-schema manifest. | Low. | A new record type fails CI until the manifest is updated. |
| 7 | `Vaultify/App/AppEnvironment.swift:329-364` | Add the four attest accounts to `eraseEverything()`. | Very low. | Erase Vault, then Share Link re-registers. |

**Immediate workaround before any of this ships:** delete the app on the affected device and install fresh. The App Attest key dies with the app, `DCError.invalidKey` fires (`LooxLinkAttestation.swift:38`), `resetKey()` runs, and the device re-registers against production. *Do this only after step 1 — otherwise the reinstall restore will lose the passkeys again.*

---

## 5. Open questions you must answer

1. **CloudKit Console, container `iCloud.com.bervion.vaultify`, Production environment: does record type `VaultPasskey` exist?** This is the single observation that converts Issue 2 from inference to fact. I cannot read it (`xcrun cktool get-teams` → "No management token found"). While you are there, check the other five pending types.
2. **On the fresh device that lost the passkeys, did Share Link work?** Under my Issue-1 mechanism a genuinely virgin device mints and registers a fresh key against production and Share Link **must** succeed. If it also failed there, there is a second, independent App Attest cause and step 5 (Worker logging) becomes the first move, not the last.
3. **Which surface actually showed "couldn't prove it's a genuine Loox install" for "share to computer"?** `QuickViewApprovalFlowModel.swift:244-250` rewrites its errors to "Start again on the computer." If you saw the attest wording there, tell me where in the flow — it means a Quick View call site I have not accounted for.
4. **Are both devices on ≥ v1.36.0?** Passkeys were not in CloudKit at all before that (`CHANGELOG.md`, 2026-07-17). A source device that never ran ≥1.36 with sync on never had the chance to upload, schema or no schema.
5. **Do personas / email aliases / forwarding inboxes / Watchtower audit history sync across your two devices?** If they do, a Console deploy happened after 260717 and Issue 2's diagnosis needs re-examination. If they do not, that confirms the whole pending batch and is free evidence.
6. **Do you still have any device holding the old passkeys?** If yes, take an encrypted `.vaultify` export **now** (`ExportView`) — that path is verified lossless and recovers them today, independent of the schema deploy.
7. **Settings → iCloud Sync on a TestFlight device: green "Last sync <time>", or a CloudKit error string?** Green means the failure is per-record and silent (expected); an error naming a record type names the culprit outright.

---

### Not causes — do not chase

- `LOOX_CAP_SIGNING_KEY_PKCS8_B64` / `cap-2026-02` — live, unexpired, matching, and not on the failing path (§2.1).
- Missing `TUIST_LOOX_LINK_PROD_TOKEN` — `index.ts:116-120` only reads `APP_CREATE_TOKEN` in `off`/`shadow`; it is never consulted in `required`.
- Missing `com.apple.developer.devicecheck.appattest-environment` — true, but macOS-only on that entitlement, identical for Debug and local Release, and `register.ts` never calls `enforceEnvironmentPolicy` (`app-attest/attestation.ts:143` is dead code; `parseAttestation` returns `environment:'unknown'`). Zero correlation with the symptom.
- The `PasskeyBackupStatus` "Backed up" badge (`PasskeyBackupStatus.swift:16-23`, `PasskeyDetailSheet.swift:80-91`) — it reads WebAuthn BE/BS bits and the sync toggle, has three call sites total, and cannot exclude a record from anything. A wrong badge, not a cause.
- `SyncCoordinator.swift:98` gating the zone subscription on sync success — real coupling wart, but type-agnostic; it cannot make passkeys uniquely fail while items sync.
