# Phase 2 — Consent, defaults, and erase completeness

Five agents. Three of the four collision files live here, so ownership is exclusive and
enforced: `SettingsStore.swift`, `AppEnvironment.swift`, and the onboarding flows each
have exactly one owner.

---

## Agent 2A — sole owner of `SettingsStore.swift`

All four defaults are decided together as one reviewed change, because they land within a
few lines of each other and three separate agents would otherwise conflict.

| Flag | Current | Target | Source |
|---|---|---|---|
| `analyticsEnabled` | `true` (`:238`) | **`false`** | D1 |
| `crashReportingEnabled` | `true` (`:239`) | `true` (unchanged) | D1 |
| `showWebsiteIcons` | `true` (`:237`) | `true` (unchanged) | D2 |
| `iCloudSyncEnabled` | `false` (`:234`) | `false` (unchanged; the bug is that onboarding overrides it) | D5 |

Verify the analytics flip actually stops the first network call. `AnalyticsEngine` and
`CrashReporter` share a single Firebase `configure()` gate but hold separate consent
flags — confirm that turning analytics off does not silently keep uploading, and that
turning crash reporting off does not disable analytics.

**Tests** — new `VaultifyTests/SettingsStoreTests.swift` and `SyncOptInContractTests.swift`:

- Pin each of the four defaults. There is currently **zero** coverage of any of them.
- Pin ADR-2 independence: setting `approvalModeEnabled` never touches `iCloudSyncEnabled`
  and vice versa. Verification confirmed the invariant holds across 35 call sites but
  nothing tests it, so the next refactor can break it silently.
- Pin that erase clears both flags.

---

## Agent 2B — sole owner of `AppEnvironment.swift` and the erase paths

**Also owns:** `Vaultify/Features/Settings/SettingsScreen.swift` erase path,
`MacSettingsView.swift` erase path, `CloudSyncService.eraseRemote()`,
`ApprovalShareService.revokeAllOwned()`, `LooxLinkService`.

Four separate findings land in the same ~60 lines (`eraseLocalState`, lines 384-416, plus
`eraseEverything`, 352-360). One workstream, one owner, or you get four PRs racing.

### What is actually wrong

`eraseEverything()` launches CloudKit erase, owned-share revoke, and inbox disarm as three
unretained, unawaited `Task {}`s with `try?` swallowing at every layer
(`AppEnvironment.swift:352-359`, `CloudSyncService.swift:136-145`,
`ApprovalShareService.swift:522-527`, `InviteInboxService.swift:173-183`), then calls
`eraseLocalState()`. No result is ever inspected or shown.

Two corrections to the audit's framing, both verified:

- **"Fail-open" is not the design.** The relay/alias step is already fail-**closed** on
  iOS: `SettingsScreen.swift:47-58` blocks the erase, shows a "Network needed" alert, and
  proceeds only via an explicit "Erase Anyway" that states the consequence. The right
  pattern was built once and never applied to the other three steps or to the Mac.
- **The ordering hazard is narrower than claimed.** `ApprovalShareService`'s zone registry
  is plain `UserDefaults` and is not wiped by `eraseLocalState()`; `eraseRemote()` does not
  read `iCloudSyncEnabled`; CloudKit auth is the iCloud account, not vault key material.
  All four types are `@MainActor`, so the Task bodies provably cannot start until the
  synchronous erase returns. The claim that local wipe breaks all three remote steps is
  **refuted**.

### M8 — Quick Links are never revoked (the real blocker)

Erase destroys the revoke tokens instead of using them, leaving up to **30 days**
(`LooxLinkConfig.swift:74`, 2,592,000s) of live encrypted snapshot. The content key is in
the URL fragment, so anyone holding the URL — chat history, clipboard manager, browser
sync — still decrypts the item. Because the only revoke credential was just deleted from
the Keychain, neither the user nor support can ever kill it.

- Add `LooxLinkService.revokeAllForErase() async -> (attempted: Int, failed: [Record])`,
  modeled on the existing `RelayService.disableAllForErase()`.
- In `eraseEverything()`, capture non-expired records from `looxLinks.records` and await a
  bounded bulk revoke **before** `eraseLocalState()` runs. The ordering is load-bearing.
- Extend `SettingsScreen.eraseWithRelayTeardown()` (`:47-58`) so the pre-erase gate covers
  quick links as well as aliases, and widen the "Network needed" copy accordingly.
- Optionally add `LooxLinkRecordStore.wipe(keeping:)` so records that failed to revoke are
  the only thing retained.

Failure handling is part of the contract, not a nicety: if a Quick Link revoke fails,
either retain enough revoke record and token to retry it later, or define what the user
just did as a **local-only erase** and say so. What must not happen is the current
behavior, where "Erase Anyway" destroys the revoke tokens while the links stay live for up
to 30 days with nobody able to kill them.

Required repro before this is called done: airplane mode, and app killed mid-erase, with
the link checked from a second device.

### M9 — macOS bypasses relay teardown

**Scope note:** macOS is not shipping this round. Fix it through the shared coordinator
because it is the same code path, but a purely macOS-only defect must not become a blocker
for the iOS RC.

`MacSettingsView.swift:180` calls `env.eraseEverything()` directly. Aliases keep forwarding
to the user's real inbox indefinitely with no warning, and `eraseEverything()` then drops
the whole `Vault` CloudKit zone (`CloudSyncService.swift:138`), destroying the alias list on
every device so the user can no longer see or disable them from anywhere.

Move the precondition out of the iOS view into a shared coordinator (or an async
`eraseEverything()`), and route both platforms through it.

### D6 — the two-mode contract

- "Erase on this device" and "Erase everywhere" as distinct, clearly-worded actions. The
  current copy says "on this device" in all three languages while the action also destroys
  remote state — that alone is a copy bug.
- For "erase everywhere": await each remote step with a bounded timeout, show a per-step
  result, and offer Retry or "Erase Anyway" — the pattern `SettingsScreen.swift:47-58`
  already implements correctly.
- **Do not build speculative cross-launch retry state.** Re-running `revokeAllOwned()` on
  next launch based on leftover `UserDefaults` puts recovery guesswork inside the most
  safety-critical function in the app. Ship the observable failure, not the invisible retry.

### Residue purge — three more things survive erase

- `<AppGroup>/Favicons/*.img` — a plaintext directory listing of every site the user has a
  login for. `AppEnvironment.swift:384-416` never touches it.
- `<AppGroup>/Attachments/*.enc` — `AttachmentStore` has no erase API at all.
- Artifact files written outside the artifact root (Phase 3, P1-03) are invisible to
  `reconcile()` and survive `eraseAll()`.

### Test isolation

Mark tutorial flows `.skipped` under UI-test isolation in `AppEnvironment.init` — this is
Phase 4's fix but it lands in this file, so this owner implements it. It unblocks **both**
failing UI tests.

**Tests:** the entire erase path currently has **zero** automated coverage. Add
per-step-outcome tests, an offline path test, and a test that the favicon and attachment
directories are empty afterward.

---

## Agent 2C — sole owner of `FaviconService.swift` and `FaviconView.swift`

D2 keeps the network design as-is: default ON, Google `s2/favicons`. These are the
mechanical defects that are wrong regardless of that decision.

1. **Ephemeral, cookieless `URLSession`** with a bounded timeout. `URLSession.shared` puts
   the requests in the shared cookie jar, so Google's `NID` cookie ties every login host to
   one persistent pseudonym across the whole session.
2. **Debounce and validate the host before fetching.** Typing a URL in the item editor
   currently fires a lookup per keystroke, sending partial and prefix hostnames.
3. **Task-coalescing for duplicate hosts.** When two items share a host, only one row gets
   its icon on first load; the others silently stay blank.
4. **Negative cache with a cooldown.** Failed lookups are never remembered, so every
   offline or error-path host is re-requested on every render.
5. **Hashed cache filenames.** Today it is `\(host).img` in the App Group — a plaintext
   inventory of the user's accounts readable by anything with group access. Use a keyed
   HMAC.
6. **`.completeFileProtection` on write** (`:50`). Every other write in this codebase uses
   `[.atomic, .completeFileProtection]`; this one uses none.
7. **`clearCache()` API** for Agent 2B's erase path and for the settings toggle.
8. **Opt-out flag for the import preview** so a bulk import does not enumerate the entire
   imported vault to Google in one burst.

**Do not** switch to direct `https://<host>/favicon.ico` — it leaks the user's IP to every
site in their vault on app open and reveals internal hostnames, which is arguably worse.
**Do not** stand up a self-hosted proxy — that makes *Loox* learn every domain the user has
an account with, which breaks "we never see your data" more fundamentally than Google does.
Revisit post-launch.

**Tests:** no request when the toggle is off; one request per unique host per render pass;
no request for a partial hostname; cache filenames contain no plaintext host; cache empty
after erase.

---

## Agent 2D — sole owner of the onboarding flows

**Owns:** `OnboardingFlow.swift`, `EmergencyKitView.swift`, `EnableBiometricView.swift`,
`JoinVaultFlow.swift`, `WelcomeLandingView.swift`.

**Blocked by OPEN-2.**

### D5 — explicit iCloud consent

`OnboardingFlow.swift:143` unconditionally sets `env.settings.iCloudSyncEnabled = true`
after `createVault`, and the comment justifying it is factually wrong — which is likely how
this survived review. Delete it and the comment.

Sharper than the audit recorded: **the first CloudKit write happens on a 3-second debounce
during the name step**, before the user has seen anything resembling a choice.

Add the consent affordance to the step that already owns the recovery story
(`EmergencyKitView`). Not preselected. Copy must explain what sync does and does not do,
and — per OPEN-2 — that cross-device recovery depends on it.

What actually leaves the device when sync is on, for the copy and for Phase 1B's policy:
ciphertext, the recovery envelope, plaintext `FolderRecord.iconAsset`/`colorRaw`/
`sortIndex`/timestamps, and via `DeviceRegistryService.publish()` the device name,
marketing model name and app version. Folder **names** are sealed
(`FolderRecord.swift:11-12`), contrary to the audit — the honest version is still bad
enough, and `SyncSettingsView.swift:39` already discloses precisely this set.

### Onboarding error handling

- `generateRecoveryKit()` wrapped in `try?` is not a swallowed error, it is an
  **unescapable dead-end**: an empty key leaves a permanent `ProgressView` with no retry.
  Severity-total even at low probability. Add real error handling and a retry.
- `enableBiometric()` swallows errors and still advances to done, so the user believes
  biometrics are on when they are not. Surface the failure.
- Replace the SF Symbol `chevron.backward` (`:119`) with the Polaris equivalent.
- Remove the reduce-motion `asyncAfter`.

**Do not** reword "Add your first item" on the done screen. An identity is seeded, but it
is a profile the app created, not something the user added — the sentence is defensible,
and retiring an EN key plus VI and JA translations for a nit is negative value while
`Localizable.xcstrings` is contended.

**Tests:** after `createVault` with no consent given, `iCloudSyncEnabled` is false and no
CloudKit write occurs.

---

## Agent 2E — iPhone landscape shell (M13, mandatory in both OPEN-1 branches)

**Owns:** `AdaptiveRootView.swift`, plus a new pure-logic test.

`AdaptiveRootView.swift:20-28` keys only off `horizontalSizeClass`, so an iPhone 16 Pro Max
in landscape reports regular horizontal and gets the **iPad sidebar shell**: the tab bar
disappears, a pinned `NavigationSplitView` sidebar takes 200-320pt of a compact-height
screen, `navigator` becomes nil so every push changes from a UIKit full-screen slide to an
in-column SwiftUI push, and the sidebar-only search field (with the Phase 6 clear bug)
becomes the search entry point. Rotating back tears the sidebar down and, per M12, wipes any
open editor draft.

Fix: require **both** size classes regular. Extract the branch into a pure
`AdaptiveShell.layout(horizontal:vertical:)` and pin the four-case matrix in
`VaultifyTests`, so this cannot regress silently.

This is an iPhone bug on the flagship device during an ordinary gesture. It does not go away
if iPad is dropped.

---

## Integrator

Merge `reports/strings-2*.json` into `Localizable.xcstrings`; EN + VI + JA on every key;
`tuist generate && make check`.

## Phase exit criteria

- [ ] Four defaults pinned by tests; ADR-2 independence pinned
- [ ] Fresh create leaves sync off until the user chooses; no CloudKit write before consent
- [ ] Erase awaits every remote step, reports per-step outcome, and revokes Quick Links first
- [ ] macOS erase routes through the same coordinator as iOS
- [ ] Favicon, attachment, and artifact residue all cleared by erase
- [ ] Favicon service: ephemeral session, debounced, coalesced, hashed filenames, protected
- [ ] Recovery-kit and biometric failures are recoverable and visible
- [ ] Plus/Max-class iPhone landscape stays in the tab shell; matrix test green
