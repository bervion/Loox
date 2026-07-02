# Red-Team Plan Review — Scope & Complexity Critic + Contract Verifier

Plan: `plans/260702-1011-passkey-deep-ios-integration/` (plan.md + phases 1–7)
Reviewer role: hostile SCOPE/COMPLEXITY critic; assigned verification role: CONTRACT VERIFIER.
Constraint respected: EXPANSION scope, envelope-key (D2), attach-to-login (D3) are user decisions — NOT challenged. Findings attack complexity/rework/false premises WITHIN the chosen scope.

---

## Finding 1: Phase 5 builds password-change re-provisioning on a false premise — the Vault Key never changes on password change

- **Severity:** Critical
- **Location:** Phase 5, "Implementation Steps" step 1 + Risk Assessment "Password-change window" + step 6 test "re-provision on password change"
- **Flaw:** Step 1 claims "envelope private key sealed under OLD vault key becomes garbage → regenerate; hook the existing change-password + erase paths", and the risk section designs an ordering protocol ("open+migrate all envelope records FIRST, then rotate envelope... Encode as an explicit step in the change-password path"). This is factually wrong. Vaultify's key hierarchy wraps a **permanent** random Vault Key: `changeMasterPassword` (and `recover`) unwrap the SAME key bytes and only re-wrap the password path (`rewrapWithPassword` touches `wrappedByPassword`/`kdfSalt`/`kdf` only). The envelope private key sealed under the Vault Key stays openable forever. Only `resetVault()` (erase) destroys key material — and there the fix is deleting one file, not a "re-provision" flow.
- **Failure scenario:** Implementer wires envelope rotation into the change-password path, writes the migrate-first ordering logic and its test — all dead code solving a non-problem. Worse, rotating the envelope keypair during password change **introduces** a race the current design doesn't have: a silent upgrade in flight (extension sealing to the old public key) while the app rotates produces exactly the orphaned-unreadable-record the paragraph claims to prevent. Estimated 2–3h of the 8h budget spent adding risk.
- **Evidence:**
  - `Vaultify/Security/VaultSession+Recovery.swift:43-55` — `changeMasterPassword` unwraps then `rewrapWithPassword(new, vaultKey: keyBytes, ...)`; `:57-66` rewrap only replaces `wrappedByPassword`.
  - `Vaultify/Features/Settings/ChangeMasterPasswordView.swift:3-4` — doc: "**The Vault Key is unchanged**, so biometrics and the Emergency Kit stay valid."
  - `VaultifyCore/Crypto/KeyHierarchy.swift:6-9` — "generated once at vault creation and only ever stored *wrapped*."
  - `Vaultify/Security/VaultSession+Recovery.swift:70-76` — `resetVault()` already wipes key material (`VaultKeyBundle.wipe()`).
- **Suggested fix:** Delete the password-change hook, the ordering protocol, and the re-provision test from Phase 5. Keep only erase-path cleanup — which is free if Finding 3 is applied (envelope fields live in `VaultKeyBundle`, wiped by `resetVault()` today), else one `removeItem` in the erase path.

## Finding 2: Phase 1's signature changes break the extension, but the broken caller is not in Phase 1's file list — the phase cannot pass its own validation gate

- **Severity:** High
- **Location:** Phase 1, "Related Code Files" + step 4; plan.md "Validation gates (every phase)"
- **Flaw:** Contract check (assigned role): step 4 re-types `matching(...) -> [StoredPasskey]` / `all(key:) -> [StoredPasskey]` (both EXIST today returning `[PasskeySecret]` — the plan says "Add", which is wrong: same-name/same-args return-type changes replace, or create ambiguous overloads at call sites) and makes `save` return `[Data]` with real error propagation. Callers enumerated:
  - `PasskeyVault.matching` — **1 caller**: `VaultifyAutoFill/CredentialProviderViewController.swift:169`, which then reads `passkey.privateKeyRaw/.userHandle/.credentialID` (`:170-179`) — `PasskeySecret` fields; breaks when elements become `StoredPasskey`.
  - `PasskeyVault.save` — **1 caller**: `CredentialProviderViewController.swift:188` (`try? PasskeyVault.save(...)` — the exact F4 swallow Phase 1 claims to fix, untouched until Phase 2).
  - `PasskeyVault.all` — 0 external callers.
  Phase 1's file list contains only VaultifyCore files + VaultStore + tests. plan.md gates require "`make check` compiles app + extension with zero errors" **every phase** — impossible as scoped.
- **Failure scenario:** Implementer hits the compile break mid-Phase-1, improvises edits to `CredentialProviderViewController.perform()` (uncounted effort, untested extension churn), then Phase 2 rewrites that same code into `PasskeyCeremonyView` — the Phase 1 improvisation is thrown away. Pure rework.
- **Evidence:** `VaultifyCore/Passkey/PasskeyVault.swift:20,30` (existing `all`/`matching`); `VaultifyAutoFill/CredentialProviderViewController.swift:169-188`; plan.md:47. Related file-list rot: phases 2/4/5/7 all list `Vaultify/Resources/Localizable.xcstrings` — actual path is `Vaultify/Localizable.xcstrings` (find verified; `Vaultify/Resources/` holds `eff_large_wordlist.txt`).
- **Suggested fix:** Either add `CredentialProviderViewController.swift` to Phase 1's list with a minimal mechanical adaptation (and say exactly that), or keep `[PasskeySecret]` returns in Phase 1 and land `StoredPasskey` in Phase 2 where the caller is rewritten anyway. Fix the xcstrings path in 4 phase files.

## Finding 3: Phase 5's `passkey-envelope.json` rebuilds the existing `VaultKeyBundle` key-bundle mechanism

- **Severity:** High
- **Location:** Phase 5, "Architecture" (Provisioning bullet) + step 1 (`PasskeyEnvelope.swift` "keypair file I/O")
- **Flaw:** The plan creates a second versioned key file in the App Group ("store `publicKeyRaw` plaintext + `privateKey` sealed under the Vault Key in one JSON file... beside the vault file") with its own load/save/exists/integrity-check plumbing. `VaultKeyBundle` IS that mechanism already: a Codable, versioned JSON in the App Group (`SharedConfig.keyBundleURL`), `.completeFileProtection`, `load()/save()/wipe()/exists`, and an established pattern of adding new key paths as optional fields (recovery: `recoverySalt`/`wrappedByRecovery`; Level-2: `l2Salt`/`l2Kdf`/`wrappedL2SK` — all added exactly this way, "Optional → backward-compatible"). Two new optional fields (`envelopePublicKey: Data?`, `wrappedEnvelopePrivate: Data?`) give provisioning, locked-safe public-key read (bundle is already readable by the extension pre-unlock — `VaultReader.deriveVaultKey` loads it), erase-wipe for free (`resetVault()` → `VaultKeyBundle.wipe()`), and one fewer file to integrity-check for the "public-key substitution" risk.
- **Failure scenario:** ~1–2h writing duplicate file plumbing + a second wipe/erase hook + a second integrity story; forever after, two key files in the container must be kept consistent (erase, restore-from-backup, file-protection class) — a maintenance tax with zero capability gain. The HPKE seal/open functions are the only genuinely new code the phase needs.
- **Evidence:** `VaultifyCore/Keychain/VaultKeyBundle.swift:7-47` (fields, load/save/wipe/exists, optional-path precedent); `VaultifyCore/SharedConfig.swift:44` (`keyBundleURL` = `vault-keybundle.json` in App Group); `VaultifyCore/VaultReader.swift:16` (extension reads bundle while locked); `Vaultify/Security/VaultSession+Recovery.swift:71` (erase already wipes bundle).
- **Suggested fix:** Scope `PasskeyEnvelope.swift` to pure HPKE seal/open + provisioning logic over `VaultKeyBundle` fields. Delete the separate JSON file, its I/O, and the standalone erase hook from the phase.

## Finding 4: `StoredPasskey.createdAt` is a third copy of the same timestamp; Phase 3's "bridging accessor" contradicts its own goal

- **Severity:** Medium
- **Location:** Phase 1, step 3 (`StoredPasskey`); Phase 3, step 1 (key bridging)
- **Flaw:** (a) `PasskeySecret` already carries `createdAt` (sealed) and `PasskeyRecord` mirrors it (plaintext, equal by construction — `save` writes `createdAt: secret.createdAt`). `StoredPasskey { secret; createdAt; lastUsedAt }` adds a third copy; UI can read `stored.secret.createdAt`. The struct earns its existence for exactly ONE field: `lastUsedAt`. (b) Phase 3 step 1: "repository holds `SecureBytes`, PasskeyVault takes `[UInt8]` — add a bridging accessor rather than duplicating key material" — an accessor that returns `[UInt8]` from `SecureBytes` **is** a key-material copy; the sentence is self-contradictory. `AESGCM` already has `SecureBytes` overloads — `PasskeyVault` can simply accept `SecureBytes` (or gain overloads), no bridging, no copies.
- **Failure scenario:** Three createdAt sources in a security-sensitive layer invite drift the moment any path (envelope migration, Phase 7 import) sets them independently; the bridging accessor invites future callers to extract raw vault-key arrays, eroding the point of `SecureBytes`.
- **Evidence:** `VaultifyCore/Passkey/PasskeyModels.swift:14` (secret.createdAt), `:24` (record.createdAt); `PasskeyVault.swift:14-15` (equal by construction); `VaultifyCore/Crypto/AESGCM.swift:24,28` (`seal/open(_:key: SecureBytes)`); `Vaultify/Data/Repositories/VaultRepository.swift:248-253` (repo already seals with `SecureBytes` directly).
- **Suggested fix:** `StoredPasskey { secret: PasskeySecret; lastUsedAt: Date? }`. Give `PasskeyVault` `SecureBytes`-taking overloads; drop the "bridging accessor" step.

## Finding 5: `PasskeyLoginMatcher` — a new shared file + test file for a one-line predicate that already exists twice in the codebase

- **Severity:** Medium
- **Location:** Phase 4, "Architecture" + step 1 + Related Code Files (`Create: VaultifyCore/Passkey/PasskeyLoginMatcher.swift`, `Create: VaultifyTests/PasskeyLoginMatcherTests.swift`)
- **Flaw:** The rule is `host == rp || host.hasSuffix("." + rp)`. That exact expression already ships at `TwoFactorCatalog.swift:74` (`host == $0 || host.hasSuffix("." + $0)`), and the sibling AutoFill matcher `VaultItem.matchesAutoFill` lives at `VaultReader.swift:87-94` (looser, bidirectional + `contains`). Phase 4 creates a THIRD host-matching implementation, in a new file, with a `passkeys(for:in:)` convenience layer and a dedicated test file — and never mentions `matchesAutoFill`, so an implementer won't reconcile why item↔service matching and item↔rp matching use different rules in different files.
- **Failure scenario:** Three divergent matching rules in three locations; the next person tightening/loosening AutoFill matching updates one and not the others (the classic drift this codebase already flirts with between `matchesAutoFill` and `TwoFactorCatalog`). File count and test scaffolding grow for a predicate that is one line.
- **Evidence:** `VaultifyCore/VaultReader.swift:87-94`; `Vaultify/Services/Watchtower/TwoFactorCatalog.swift:74`; phase-04 step 1.
- **Suggested fix:** Same scope, simpler shape: add `VaultItem.matchesRelyingParty(_:)` (or a `Host.matchesSuffix` helper) as an extension in `VaultReader.swift` next to `matchesAutoFill`, with a doc comment contrasting the strict passkey rule vs the loose fill rule; test cases go in an existing/general test file. Drop the standalone matcher file + convenience API. (Note: Phase 4's favicon hedge is also moot — `FaviconView(urlString:category:size:)` at `Vaultify/Features/Components/FaviconView.swift:6-9` is not item-bound; `urlString: "https://\(rp)"` just works.)

## Finding 6: Phase 2/3 split reworks the registration success path Phase 2 just wrote — and Phase 2 contradicts itself on where ceremony gates live

- **Severity:** Medium
- **Location:** Phase 2, "Architecture" vs step 2; Phase 2 step 2 last bullet ("identity-store append lands in Phase 3") vs Phase 3 step 3
- **Flaw:** (a) Phase 2 rewrites the entire registration flow (confirm card, throwing save, error UI) and mandates a full manual matrix (step 6). Phase 3 step 3 then re-opens that exact success path to insert ~5 lines (identity append + replaced-ID removal) — code that has no dependency on anything else in Phase 3 (identity construction needs only AuthenticationServices, not `VaultRepository.passkeys`). The same 235-line `CredentialProviderViewController.swift` is modified in phases 2, 3, 5, and 6. (b) Internal contradiction: Architecture says "ALL ceremony decisions (algorithm check, excluded match, dedupe result, picker) run AFTER unlock inside the view; the view controller only hosts and completes/cancels" — step 2 then instructs the algorithm gate "in the view controller BEFORE showing UI" and the excluded gate "check before unlock too". Two authoritative homes for the same checks.
- **Failure scenario:** (a) The Phase 2 manual matrix (register new / excluded / assert single / multi / fallback / Face ID) must be fully re-run after Phase 3's touch — a duplicated test cycle for a change that was free to include in Phase 2. (b) The contradiction gets resolved by implementing the gates twice (VC + view), i.e. duplicated logic with two divergence points, or by churning on which text to follow.
- **Evidence:** phase-02 "Architecture" + step 2; phase-03 step 3 ("CredentialProviderViewController.swift (or ceremony view)"); phase-05 + phase-06 Related Code Files (same file again); `VaultifyAutoFill/CredentialProviderViewController.swift` (235 LOC).
- **Suggested fix:** Move the ~5-line identity append/remove into Phase 2's registration step (Phase 3 keeps app-side publication + the QuickType verification). Fix Phase 2's architecture paragraph to state explicitly: algorithm + excluded gates run pre-unlock in the VC (they need no key); post-unlock view handles dedupe/picker/persist only — one home per check.

## Finding 7: `ASPasskeyCredentialIdentity` construction planned in three places with no shared mapper — removal correctness silently depends on field-exact duplication

- **Severity:** Medium
- **Location:** Phase 3, step 2 (app: `CredentialIdentityService`) + step 3 (extension: post-registration append/remove); Phase 5, step 4 (extension: silent path append)
- **Flaw:** The secret→identity mapping (rpId, userName, credentialID, userHandle, recordIdentifier = base64url credID) is written out in Phase 3 step 2 for the app target, then re-created in the extension in Phase 3 step 3 and again in Phase 5 step 4. `CredentialIdentityService` lives in the app target (`Vaultify/Services/`) — the extension can't import it, and no shared helper is planned. Phase 3 step 3's removal path ("removeCredentialIdentities with matching passkey identities") only works if the extension-built identity matches the app-published one field-for-field; the recordIdentifier convention exists solely as prose repeated across phases.
- **Failure scenario:** One site drifts (e.g. recordIdentifier raw vs base64url, or userName fallback differs) → `removeCredentialIdentities` no-ops → stale QuickType suggestions for replaced passkeys persist until next app unlock — precisely the bug Phase 3 step 3 exists to prevent. The DRY irony: the plan creates a shared VaultifyCore file for a one-line host predicate (Finding 5) but not for the one mapping that genuinely needs cross-target consistency.
- **Evidence:** `Vaultify/Services/CredentialIdentityService.swift:8-33` (app-target only; extension nowhere references it — grep: 2 call sites, both `VaultRepository.swift:30,54`); phase-03 steps 2–3; phase-05 step 4; precedent being copied: `VaultifyAutoFill/CreateLoginView.swift:70-74` already re-implements host parsing locally instead of sharing.
- **Suggested fix:** One `extension PasskeySecret { var credentialIdentity: ASPasskeyCredentialIdentity }` in VaultifyCore (compiled into both targets); app service and both extension paths consume it. Add it to Phase 3's file list; phases 3/5 lose their inline construction text.

## Finding 8: Phase 5 embeds envelope migration inside the read path — every `all`/`matching` becomes a potential write, including mid-assertion in the extension

- **Severity:** Medium
- **Location:** Phase 5, "Architecture" ("Read path (unlocked): `PasskeyVault.all/matching` unseal envelope private key once per call, open envelope records, and MIGRATE them in place") + step 3
- **Flaw:** Turning the two read APIs into read-write hybrids means `context.save()` can fire during an assertion ceremony in the extension (`matching` is called at `CredentialProviderViewController.swift:169` in the signing path) and adds envelope-file I/O + save-failure handling to every read call site. The phase ALREADY adds an interactive-unlock hook in both targets for provisioning ("Modify: UnlockGate.swift or unlock success hook ... + same hook app-side") — that hook is the natural single migration site: at unlock, the vault key is in hand, and migration runs once, in one place, with one failure path, instead of being latent in every read.
- **Failure scenario:** A failed in-read migration save (disk pressure, container contention with the app) now has to decide whether the READ fails — new error-handling surface in the extension's sign-in ceremony for zero functional gain; tests must cover read-triggered-write interleavings instead of one idempotent unlock migration.
- **Evidence:** phase-05 Architecture "Read path" + step 3; `VaultifyAutoFill/CredentialProviderViewController.swift:169` (matching in assertion path); phase-05 Related Code Files (unlock hook already in scope, both targets).
- **Suggested fix:** Keep reads read-only (open envelope records transparently, no rewrite). Run migrate-all-envelope-records in the same unlock hook that provisions the keypair (app: `VaultRepository.reload()`; extension: post-`UnlockGate`). Same scope, one write site.

## Finding 9: Effort figures ignore the plan's own hidden work — Phase 1 "4h" and Phase 5 "8h" are not credible as scoped

- **Severity:** Medium
- **Location:** plan.md phase table; Phase 1 steps 6–8; Phase 5 steps 6–7
- **Flaw:** Phase 1's 4h must cover: flags + AAGUID + model column + a full `PasskeyVault` reshape (StoredPasskey, dedupe-by-decrypt, delete, touchLastUsed, error propagation) + `eraseAll` + TWO new test suites including hand-decoded CBOR attestation objects and exact-byte COSE vectors (`A5 01 02 03 26 ...`) and encoder boundary cases + `tuist generate`/`make test` + a manual SwiftData-migration check on an upgraded container — **plus** the unbudgeted extension-caller migration from Finding 2. Phase 5's 8h includes new HPKE code, two-target unlock hooks, the (bogus, Finding 1) password-change protocol, a Settings toggle with EN+VI copy, an envelope test suite, and manual verification of a system-controlled trigger the plan itself concedes is non-deterministic ("treat 'no upgrade offered' as non-bug" — i.e., hours of poking iOS 18 upgrade heuristics with a recent password fill).
- **Failure scenario:** P1 phases blow their boxes by ~2x; since 1→2→3→4 are strictly sequential, the slip compounds and the "shippable release after phase 5" line moves by days, pressuring exactly the corners (tests, VI strings, manual matrix) the validation gates exist to protect.
- **Evidence:** phase-01 steps 4,6,7 vs effort "4h" (phase-01 frontmatter); phase-05 steps 1–7 + Risk "Apple behavior drift" vs "8h"; Finding 1–3 cuts are the honest way to make 8h real.
- **Suggested fix:** Phase 1 → 6–8h (or move the StoredPasskey re-typing to Phase 2 per Finding 2 and keep 4h). Phase 5 → keep 8h ONLY after deleting the password-change protocol (F1), the parallel key file (F3), and in-read migration (F8); state the silent-upgrade manual check as time-boxed with a documented "couldn't trigger" exit.

---

## Contract verification summary (assigned role)

| Symbol | Callers found (grep, non-defining) | Plan accounts for it? |
|---|---|---|
| `CredentialIdentityService.refresh(items:)` | 1 — `Vaultify/Data/Repositories/VaultRepository.swift:54` | YES — Phase 3 modifies VaultRepository in the same phase |
| `CredentialIdentityService.clear()` | 1 — `VaultRepository.swift:30` | YES — unchanged |
| `PasskeyVault.save` | 1 — `VaultifyAutoFill/CredentialProviderViewController.swift:188` (`try?`) | **NO — Finding 2** (file absent from Phase 1 list) |
| `PasskeyVault.matching` | 1 — `CredentialProviderViewController.swift:169` (+ field reads `:170-179`) | **NO — Finding 2** |
| `PasskeyVault.all` | 0 external (internal use in `matching` only) | YES (re-type safe; wording "Add" inaccurate — it exists at `PasskeyVault.swift:20`) |
| `WebAuthn.register` / `WebAuthn.assertion` | 1 each — `:183` / `:171` | YES — no signature change (flags/AAGUID internal) |
| `UnlockGate` | 3 — `AutoFillView.swift:12`, `SavePasswordView.swift:14`, `OneTimeCodeView.swift:12` | YES — Phase 2 adds a 4th consumer, gate signature untouched; Phase 5's provisioning hook touches all 4 flows (noted in F8 fix) |
| Tests importing changed symbols | 0 (no passkey tests exist — `VaultifyTests/` listing verified, F12 accurate) | YES |

Factual errors found in plan text: Phase 5 vault-key-rotation premise (F1); `Vaultify/Resources/Localizable.xcstrings` path wrong in phases 2/4/5/7 (actual: `Vaultify/Localizable.xcstrings`); Phase 1 "Add `all`/`matching`" — both already exist (`PasskeyVault.swift:20,30`).

Unresolved questions: none blocking — all findings grep-verified against working tree @ main (v1.6.0, clean).
