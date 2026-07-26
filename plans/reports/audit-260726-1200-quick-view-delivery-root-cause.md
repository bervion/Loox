# Quick View "Open on Computer" — root-cause report (issue 3)

Date: 2026-07-26 · Scope: read-only forensics across
`/Users/bervion/Developer/Projects/mobile/ios/Vaultify` and
`/Users/bervion/Developer/Projects/frontend/looxpassword`.
All D1 queries were `SELECT`-only (`rows_written: 0` in every result).

---

## 1. Verdict

**Issue 3 is App Attest. It is the SAME bug as issue 1.** The app instance can no longer
obtain or use a server-known App Attest key, so the payload upload cannot present a valid
assertion; `workers/loox-quick-view/src/payload-upload.ts:115-119` returns `401` **before**
`getSessionStub(env, sessionId).claim(...)` at `:144`, which is the only writer of the
`APPROVED` state (`session-do-mailbox.ts:73`). The sealed payload therefore never reaches the
session Durable Object, the SSE stream keeps emitting `CREATED`, and
`open.looxpassword.com` sits on the QR/waiting view until the 180 s TTL flips it to
"Session expired". The redesigned `/open` page is **not** implicated — it is flow-neutral
(DOM ids, CSP, SSE and the crypto/flow modules are unchanged and verified live). The exact
rung that fails (`register` 400 vs `upload` 401 reason code) is currently **unobservable**,
because `app-attest/register.ts` returns the `AttestError` code on the wire but logs nothing
server-side — that observability hole is the concrete thing blocking a one-shot fix, and it is
the first item in §4.

Proof that this is one bug, not two: `loox-quick-view-production.attest_keys` and
`loox-link-production.attest_keys` are both frozen on the same app instance, days apart
(`2026-07-08 16:40:53` and `2026-07-11 17:32:11` UTC), and `loox-link`'s 401 is exactly the
string the user reports in issue 1 (`LooxLinkAPIClient.swift:18/:201` →
"This app couldn't prove it's a genuine Loox install.").

---

## 2. Causal chain (user approves → page never renders)

1. `QuickViewApprovalFlowModel.approve()` — Face ID → compose → seal → assert → upload
   (`Vaultify/Features/Sharing/QuickView/QuickViewApprovalFlowModel.swift:165-240`).
2. `QuickViewCanonical.canonicalUploadBody(...)` at `:197`, then
   `QuickViewAttestation.assertUpload(...)` at `:199`
   (`QuickViewAttestation.swift:47-70` → `assertUploadOnce` `:72-82`).
3. `registeredKeyId(api:)` (`QuickViewAttestation.swift:108-134`) returns the stored keyId, or
   mints one and calls `register(...)` (`:137-147`) → `POST /v1/quick-view/attestation/register`.
4. **Server rung A — registration.** `handleRegister` consumes the single-use challenge at
   `workers/loox-quick-view/src/app-attest/register.ts:56`, then verifies chain + structure at
   `:62-85`. On failure it returns `400 {error: <AttestError code>}` (`:87-90`) — **and logs
   nothing**. The client drops the key (`QuickViewAttestation.swift:120-132`) and rethrows.
5. **Client fail-closed.** `assertUpload` returns `nil`; `QuickViewApprovalFlowModel.swift:206-208`
   (`if QuickViewConfig.assertionRequired, assertion == nil { throw .unauthorized }`, shipped in
   `b0bd42b3`, v1.37.1) aborts before the POST. The catch-all at `:247-253` collapses it to
   `"Start again on the computer."` — the phone shows an error, the browser shows nothing new.
6. **Server rung B — upload.** If the app *does* hold a key and sends headers,
   `verifyUploadAssertionCrypto` (`quick-view-upload-assertion.ts:63-116`) rejects with
   `key_unknown` (`:75`), `assertion_signature_invalid` (via `:99`) or `counter_replay` (`:108`);
   `payload-upload.ts:115-119` returns `401`. This path is entirely read-only against D1 — no
   counter advance, no challenge consume — which is exactly why the tables look frozen.
7. **Nothing claims the session.** `claim()` (`payload-upload.ts:144`) never runs, so
   `claimPayload` (`session-do-mailbox.ts:58-73`) never writes `state: 'APPROVED'`. `handleBind`
   is advisory and never touches `state` (`session-do.ts:175-176`).
8. **Browser.** `handleEvents` (`session-events.ts:25-49`) mirrors `stub.status()` → keeps
   emitting `CREATED`; `onStateChange` (`open-page-script-flow.ts:119-125`) only calls
   `renderApproved()` on `APPROVED`, so the page stays on `#view-waiting` with the QR and the
   countdown, then `wipeAndClose('expired')` renders "Session expired" at
   `CREATE_TO_APPROVAL_TTL_MS = 180_000` (`session-do.ts:46`). **"Fields never arrive."**

### The live evidence

| Fact | Command / source |
|---|---|
| Prod enforces required mode | `workers/loox-quick-view/wrangler.jsonc` production vars: `"QUICK_VIEW_MODE": "active", "ASSERTION_MODE": "required"` (and `capability.ts` 503-fail-closes any `active ∧ ≠required`) |
| Zero successful prod uploads since **2026-07-08 16:40:53 UTC** | `attest_keys` = 2 rows, `sign_count = 2`, `updated_at` 1783528853 / 1783528575. `commitUploadAssertion` → `advanceAssertionCounter` is the ONLY writer of `updated_at` (`key-store.ts:56-70`) |
| Registration is being **rejected right now** | `loox-quick-view-staging.attest_keys` = **0 rows**, yet challenge `ki_YVUID` was `consumed_at 2026-07-26 05:02:07`. `handleRegister` is the only consumer of `consumeChallengeReturning`, and `registerAttestedKey` is `INSERT … ON CONFLICT DO NOTHING` — with an empty table there is no conflict to hide behind. Consumed + no row ⇒ the `try` block at `register.ts:62-85` threw ⇒ HTTP 400 |
| Same shape in prod today | prod challenges consumed `04:58:00`, `05:02:06`, `05:02:06` — no new key rows, `sign_count` still 2 |
| Prod uploads were 401'd on 07-17 / 07-18 / 07-23 | 12 challenges issued in bind+upload **pairs** 2-3 s apart, **none consumed** — the upload challenge is only consumed post-claim (`payload-upload.ts:160-168`), so unconsumed = the upload never won |
| Issue 1 is the same freeze | `loox-link-production.attest_keys`: newest key `g7k/KfrJEk` created `2026-07-10 21:16:20`, `updated_at 2026-07-11 17:32:11`, nothing since |
| Backend is not the regression | `git log --since=2026-07-05 -- workers/loox-quick-view workers/loox-link` — newest commit touching the attest path is `e6bae33` (2026-07-08), the same day registration last succeeded |
| Transcript parity is intact | server binds **named fields** (`contracts/upload-assertion-transcript.ts:27-33`), and the app passes `QuickViewCanonical.canonicalUploadBody(...)` as `uploadBody` (`QuickViewApprovalFlowModel.swift:197`) — the `entitlement` sibling added in `141e0bfb` rides outside the digest. `QuickViewCanonical.uploadPath` uses `QuickViewConfig.servicePathPrefix = "/v1/quick-view"`, matching `new URL(req.url).pathname` |

---

## 3. Why it worked before and broke now

- **2026-07-08 16:36 / 16:40 UTC — it demonstrably worked, twice, in production.** Full ladder,
  end to end: challenge `djW-RGKT` consumed 16:36:14 → key `iAoEu10AT5` created 16:36:14 →
  challenge `zvtTAokO` consumed 16:36:15 → `sign_count 2`, `updated_at` 16:36:15. Same pattern
  16:40:43-53 for key `jVPx+UKUyn`.
- **The backend has not changed since.** `e6bae33` (2026-07-08, "App Attest endpoints must carry
  the `/v1/quick-view/` prefix") is the newest commit on the attest path. `wrangler.jsonc`
  production vars are unchanged. `EXPECTED_APP_ID = WDNL2F75V7.com.bervion.vaultify` in both
  envs, both workers. **There is no server-side regression commit.**
- **The break is app-instance-side and it happened around 2026-07-11.** Three independently
  deployed workers stop having successful assertions within ~6 minutes of each other:
  `loox-link` 07-11 17:32:11, relay 07-11 17:38 (prior audit), quick-view had no traffic between
  07-08 16:40 and 07-17 16:35 and then only failures.
- **There is a documented precedent for exactly this failure on this codebase.** `c01dccfd`
  (2026-07-07) — *"the stored relay keyId string no longer matched the Enclave key actually used
  to sign → `assertion_signature_invalid`, sign_count 0"* — fixed by bumping the relay Keychain
  accounts to `-v2`. **`QuickViewAttestation` and `LooxLinkAttestation` never received that
  bump**, and neither is environment-namespaced:
  - `QuickViewAttestation.swift:19` `"quick-view-app-attest-key-id"`, `:39`
    `"quick-view-app-attest-registered"`
  - `LooxLinkAttestation.swift:16` `"loox-link-app-attest-key-id"`, `:25`
    `"loox-link-app-attest-registered"`

  while the server key store **is** env-scoped (`quick-view-upload-assertion.ts:74`:
  `keyRow.env !== environment → key_unknown`) and the app switches host by build config
  (`QuickViewConfig.swift:10-14`: DEBUG → `api-staging`, Release → `api`). One `registered`
  flag therefore covers two servers, and a keyId minted against one environment is asserted
  verbatim against the other. `KeychainStore` items are `WhenUnlockedThisDeviceOnly` and
  **survive app deletion**, while the Secure Enclave App Attest key does not — so a
  reinstall/channel switch (Xcode → TestFlight) is precisely the event that leaves a stale
  keyId + a stale "registered" flag behind.
- **What `b0bd42b3` (2026-07-18, v1.37.1) did and did not do.** It only changed the *symptom*
  (silent 401 → visible error) and added the `[quick-view-upload-assertion-required]` server log.
  It is not the cause: the freeze predates it by 10 days.
- **`eb9117d2` (2026-07-21, CI/release isolation) is a plausible aggravator, not the origin** —
  it postdates the 07-11 freeze. Do not spend time on it before reading the logs in §5.

---

## 4. The fix

> **Production is running UNCOMMITTED local code.** `loox-quick-view-production` was last
> deployed **2026-07-17T16:57:02Z** (version `d7937b42-dd74-4838-81ca-de6f6b9dda42`), while the
> newest commit touching that worker is `e69db01` (2026-07-17T01:48Z). `git status` in
> `looxpassword` shows a *much* larger uncommitted surface than previously reported — the whole
> marketing-site redesign (`src/app/**`, `src/components/**`, `public/**`, `src/messages/*.json`)
> plus `workers/loox-quick-view/src/{open-page.ts,open-page-script-render.ts,payload-upload.ts}`
> and the untracked `open-page-favicon.ts`.
>
> **Commit** (do not revert): the `/open` redesign files, `open-page-favicon.ts`, the
> `payload-upload.ts` debug line, the re-signed frozen vectors and the e2e-harness `putStorage`
> hook (their `canonical_bytes_hex` / `canonical_sha256_hex` are unchanged — contract intact).
> **Review before committing**: `workers/loox-config/control-plane-ledger.jsonl` (an append-only
> ledger). Nothing here needs reverting.

### 4a. Server: name the failing rung (deploy first — this is the unblocker)

`workers/loox-quick-view/src/app-attest/register.ts`

```diff
@@ -54,7 +54,10 @@
   // Atomically consume the challenge and get its bytes.
   const challenge = await consumeChallengeReturning(env, challengeId, environment);
-  if (!challenge) return json({error: 'challenge_invalid'}, 401);
+  if (!challenge) {
+    console.log('[quick-view-attest-register]', 'fail:challenge_invalid');
+    return json({error: 'challenge_invalid'}, 401);
+  }
@@ -76,7 +79,10 @@
     // The header keyId must equal the credential-derived keyId (bind them).
     if (!bytesEqual(b64ToBytes(keyIdB64), verified.keyId)) {
-      return json({error: 'key_id_mismatch'}, 400);
+      console.log('[quick-view-attest-register]', 'fail:key_id_mismatch');
+      return json({error: 'key_id_mismatch'}, 400);
     }
@@ -85,9 +91,11 @@
     return new Response(null, {status: 204});
   } catch (e) {
     const code = e instanceof AttestError ? e.code : 'attestation_failed';
+    // Server log only — the wire response already carries the code, but nothing
+    // observable existed for a device we cannot attach a debugger to.
+    console.log('[quick-view-attest-register]', `fail:${code}`);
     return json({error: code}, 400);
   }
```

`workers/loox-link/src/app-attest/register.ts` — identical change at `:50`, `:71`, `:80-83`,
with the tag `[loox-link-attest-register]`.

Deploy:

```bash
cd /Users/bervion/Developer/Projects/frontend/looxpassword/workers/loox-quick-view
npx wrangler deploy --env production
cd ../loox-link
npx wrangler deploy --env production
```

### 4b. iOS: break the stale/cross-environment key state

Mirrors `RelayAttestation`'s already-shipped `-v2` fix (`c01dccfd`) and additionally scopes the
namespace by environment, which relay still lacks.

`Vaultify/Features/Sharing/QuickView/QuickViewAttestation.swift`

```diff
@@ -17,7 +17,12 @@ nonisolated enum QuickViewAttestation {
-    private static let keyIdAccount = "quick-view-app-attest-key-id"
+    // `-v2-<env>`: the server key store is environment-scoped
+    // (key rows carry `env`; a foreign-env key resolves to `key_unknown`), so the
+    // client store must be too — a DEBUG build talks to api-staging and a Release
+    // build to api, and one shared "registered" flag lets a key minted against one
+    // server be asserted against the other. The version bump also forces a single
+    // clean generateKey -> register -> assert cycle, clearing any stale keyId whose
+    // Enclave key no longer exists (survives app deletion; the Enclave key does not).
+    private static let keyIdAccount = "quick-view-app-attest-key-id-v2-\(QuickViewConfig.environment)"
@@ -37,7 +42,7 @@
-    private static let registeredAccount = "quick-view-app-attest-registered"
+    private static let registeredAccount = "quick-view-app-attest-registered-v2-\(QuickViewConfig.environment)"
```

`Vaultify/Features/Sharing/LooxLink/LooxLinkAttestation.swift` (no `LooxLinkConfig.environment`
exists, so inline the build split)

```diff
@@ -14,7 +14,12 @@ nonisolated enum LooxLinkAttestation {
-    private static let keyIdAccount = "loox-link-app-attest-key-id"
+    /// See QuickViewAttestation: the server key store is environment-scoped, so the
+    /// client keyId + "registered" flag must be too, and the version bump forces one
+    /// clean generateKey -> register -> assert cycle on every device.
+    #if DEBUG
+    private static let keyIdAccount = "loox-link-app-attest-key-id-v2-staging"
+    #else
+    private static let keyIdAccount = "loox-link-app-attest-key-id-v2-production"
+    #endif
@@ -23,7 +28,11 @@
-    private static let registeredAccount = "loox-link-app-attest-registered"
+    #if DEBUG
+    private static let registeredAccount = "loox-link-app-attest-registered-v2-staging"
+    #else
+    private static let registeredAccount = "loox-link-app-attest-registered-v2-production"
+    #endif
```

No `tuist generate` needed (no new files). `make check` to compile.

### 4c. Do NOT do these

- **Do not** lower `ASSERTION_MODE` — `capability.ts` fail-closes prod to 503 on
  `active ∧ ≠required`, and it would open the blind mailbox.
- **Do not** reorder `consumeChallengeReturning` below the verification in `register.ts`
  (previously refuted): the client always fetches a fresh challenge
  (`QuickViewAttestation.swift:138`) and drops the key on any register failure, so nothing is
  retryable and the consumed-challenge rows are currently the *only* forensic signal you have.
- **Do not** chase the `/open` redesign, the `.hidden !important` rule, the re-signed vectors,
  ENTITLEMENT_MODE, the config-signing root key (`cap-2026-02`), SSE/CSP/COEP, or
  `bootstrap()`'s catch. All ruled out with evidence.
- One unrelated real defect worth a separate ticket: `ctx.roundRect` in
  `open-page-script-render.ts:64` has no feature detection and sits inside `bootstrap()`'s try,
  so old Safari/Firefox get a dead page with no QR. It cannot be issue 3 (the reporter scanned
  a QR), but it will bite someone.

---

## 5. Verification plan

**Step 0 — one cheap question that partitions the whole problem.** Ask what the *computer*
screen showed:
- QR still up with the countdown, then **"Session expired"** (~3 min) → confirmed, this report
  holds.
- Stuck on **"Approved on your phone — verifying…"** → the upload was ACCEPTED, `claim()` ran,
  and the fault is downstream in `popFlow()` (`open-page-script-flow.ts:137-178`). That would
  refute the App Attest chain and make issue 3 a *different* bug. (Note the "verifying" view is
  often a sub-second flash, and `popFlow`'s catch renders the "Unavailable" terminal view — a
  genuinely frozen spinner means a fetch that never settles.)

**Step 1 — reproduce with both logs open** (after deploying 4a):

```bash
cd /Users/bervion/Developer/Projects/frontend/looxpassword/workers/loox-quick-view
npx wrangler tail loox-quick-view-production --format pretty
```

Watch for, in order:
- `POST /v1/quick-view/attestation/register 400` plus **`[quick-view-attest-register] fail:<code>`**
  → registration is the failing rung. `cert_chain_invalid` / `not_apple_rooted` = chain;
  `nonce_mismatch` = clientDataHash disagreement; `app_id_mismatch` = provisioning/app-id;
  `key_id_mismatch` = header/credential binding.
- **`[quick-view-upload-assertion-required] fail:<code>`** (already deployed,
  `payload-upload.ts:117`) → the upload is the failing rung. `key_unknown` = the device is
  asserting with a key this environment never registered (exactly what 4b fixes);
  `assertion_signature_invalid` = stale keyId vs. signing key (the `c01dccfd` pattern, also 4b);
  `counter_replay` = the D1 row is ahead of the device.
- **No `/payload` request at all** → the client fail-closed at
  `QuickViewApprovalFlowModel.swift:206-208`; the register leg is the fault.

**Step 2 — device side, in parallel.** Console.app, subsystem `com.bervion.vaultify`, category
`quick-view-attest`. The relevant lines already exist: `"key register failed, dropping key: …"`
(`QuickViewAttestation.swift:127`, and `describe()` surfaces the server's code through
`QuickViewAPIError.server(status:code:)`), `"upload assertion failed: …"` (`:65`),
`"re-keyed upload assertion failed: …"` (`:61`), `"bind assertion skipped: …"` (`:103` — fires
earliest, cheapest signal).

**Step 3 — confirm the fix moved D1.** After a TestFlight build with 4b and one successful
open-on-computer:

```bash
npx wrangler d1 execute loox-quick-view-production --env production --remote \
  --command "SELECT substr(key_id,1,10) k, sign_count, datetime(updated_at,'unixepoch') u FROM attest_keys ORDER BY updated_at DESC LIMIT 3"
```

Success = a **new** `key_id` row with `updated_at` at your repro time and `sign_count ≥ 2`.
A frozen `updated_at` means the upload assertion is still being rejected.

**Step 4 — regression gate.** `npx wrangler d1 execute … "SELECT count(*) FROM attest_keys"` on
`loox-quick-view-staging` should stop being `0` the first time a DEBUG build attests.

---

## 6. Open questions

1. **Which view did the computer show** — "Session expired" with the QR up, or a frozen
   "Approved on your phone — verifying…"? This is the single highest-value answer and it is
   free (§5 Step 0).
2. **What exact `AttestError` code does register return?** Genuinely undetermined today —
   `register.ts` logs nothing and I have no Cloudflare token with Workers Observability read.
   Everything in §4b is the highest-prior *candidate* fix (backed by the `c01dccfd` precedent
   and the env-scoping asymmetry), not a proven one. §4a makes it a 30-second answer.
3. **What happened to this device/app instance on 2026-07-11 ~17:35 UTC?** All three surfaces
   died within minutes. App reinstall, device restore, or a switch between Xcode-installed and
   TestFlight builds? Any of those explains a stale Keychain keyId with a dead Enclave key.
4. **Were the 2026-07-08 production registrations from a TestFlight build or a locally-signed
   Release build?** That decides whether production App Attest has *ever* worked for a
   genuinely distributed build.
5. **Who deployed the workers on 2026-07-17 from an uncommitted tree, and should the whole
   marketing-site redesign be committed as part of this?** Production drift from HEAD is a
   standing hazard independent of this bug.
6. **`RelayAttestation` is `-v2` but still not environment-namespaced** — should it get the
   same env suffix in the same change?
