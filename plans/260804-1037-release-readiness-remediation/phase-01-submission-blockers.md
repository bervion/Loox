# Phase 1 — Submission blockers

Five agents, two repos, exclusive file ownership. Everything here is something App Review
sees directly.

**Critical context:** the paywall is **not dark during App Review.**
`LooxEntitlementStore.swift:145-167` grants beta purchase access when
`Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"` — true for both
TestFlight and App Review — so `purchasesEnabled` is true regardless of
`LooxMembership.launchEnabled`. A reviewer reaches the paywall from `ProfileScreen`,
`LooxHubScreen`, or any gate sheet, and taps the two links Apple explicitly checks.
`LooxMembership.swift:19-20` already declares those pages a launch gate, and the file
contradicts itself two lines up.

---

## Agent 1A — frontend routing and claims

**Repo:** `/Users/bervion/Developer/Projects/frontend/looxpassword`

**Owns:** `src/middleware.ts`, `src/messages/en.json`, `src/messages/vi.json`,
`src/components/home-compare.tsx`, `content/blog/{en,vi}/share-access-not-secrets.mdx`,
`scripts/claims-gate.sh`, new `scripts/routes-gate.sh`, `scripts/deploy-marketing.sh`,
`package.json`.

**Must not touch:** `src/i18n/routing.ts`, and do not create `messages/ja.json` (OPEN-4).

### 1A.1 Legal route aliases

`https://looxpassword.com/terms` and `/privacy` return **404** (verified live);
`/policies/terms` and `/policies/privacy` return 200.

The middleware already special-cases `/open` and `/o` before delegating to
`intlMiddleware` — follow that pattern rather than `next.config.ts` redirects, because the
existing vanity-path handling proves it works on the OpenNext/Cloudflare deployment.

Requirements:
- 308 (permanent) for `/terms` → `/policies/terms`, `/privacy` → `/policies/privacy`.
- Generate the `/vi` twins from `routing.locales` rather than hardcoding, so adding a
  locale cannot silently drop an alias. `localePrefix: 'as-needed'` means the default
  locale has no prefix and every other locale does.
- Also alias `/security` → `/policies/security` for symmetry.
- Aliases must **not** enter `src/app/sitemap.ts` — the `/policies/*` canonicals are
  already there and duplicate URLs dilute them.

Permanent redirects matter beyond this release: builds already in the wild point at the
404 URLs and cannot be updated.

### 1A.2 Correct the false privacy claims

Given D1 (analytics opt-in, crash opt-out) and D2 (favicon unchanged, Google s2), the
site currently makes claims the shipping app contradicts.

- `src/components/home-compare.tsx:13` — CMP row 7 renders ✓ for "No analytics or
  tracking SDKs" against six **named** competitors (`:17`). This is comparative
  advertising, not loose copy. Change the row to n/a, retitle it to something defensible
  (e.g. "No ad identifiers"), or remove it.
- `src/messages/en.json` and the mirrored lines in `vi.json` — rewrite the absolute
  claims. The defensible version after D1: no ad identifiers, no cross-app tracking,
  analytics off unless the user turns it on, crash diagnostics on by default and
  switchable off, vault contents never readable by anyone but the user.
- `content/blog/{en,vi}/share-access-not-secrets.mdx` — same sweep.

Every claim must be true of the **shipping default**, not of the best-case configuration.

### 1A.3 Extend the gates

`scripts/claims-gate.sh` already exists and is the right mechanism — it currently checks
only `/` and `/vi`, and one phrase it forbids is live elsewhere on the site.

- Widen the page list past `/` and `/vi`.
- Add the newly retired phrases from 1A.2 to `FORBIDDEN`.
- New `scripts/routes-gate.sh`: assert 200 for `/policies/{terms,privacy,security}`,
  `/support`, `/contact` and the `/vi` twins, and assert 308 with the right `Location`
  for `/terms`, `/privacy`, `/security`.
- Wire both into `scripts/deploy-marketing.sh` and expose as a `routes:gate` script.

### 1A.4 Contact form honesty — NOT DONE

**This item was missed in the merged PR #5 and the implementation report did not say so.**
Still outstanding.

`src/components/contact-form.tsx:29` calls `setSent(true)` unconditionally after attempting
the `mailto:` navigation, so the form shows the success message even when nothing was sent.
Report the real outcome, or replace the success state with instructions plus the address.

---

## Agent 1B — policy content

**Repo:** `looxpassword`. **Blocked by OPEN-3 and OPEN-5.**

**Owns:** `content/policies/{en,vi}/{privacy,terms,security}.mdx`,
`src/app/[locale]/layout.tsx` (alternates/hreflang),
`src/app/[locale]/policies/[slug]/page.tsx`.

The live pages self-identify as placeholders ("This is a starter template. Replace it with
a policy reviewed by qualified legal counsel before launch") while wearing a
"Last updated 1 June 2026" chip, and the privacy page asserts "No third-party trackers or
analytics profiles" — false as shipped.

### Real data inventory the policy must describe

Written from the verified code, not from the product pitch:

| Category | What actually happens |
|---|---|
| Vault contents | AES-256-GCM under a key derived by Argon2id from the master password. Never leaves the device in readable form |
| CloudKit private DB | Ciphertext plus **plaintext** metadata: `FolderRecord.iconAsset`, `colorRaw`, `sortIndex`, timestamps; and via `DeviceRegistryService.publish()` the device name, marketing model name and app version. Folder **names** are sealed, not plaintext |
| Firebase Analytics (GA4) | Product-interaction events. **Off by default after D1**; typed catalog only, never item names/values/URLs/search terms |
| Firebase Crashlytics | Crash and diagnostic data. On by default, switchable off. No `setUserID` |
| Google favicon service | The **host of a stored login** is sent to `www.google.com/s2/favicons` when a row renders. On by default (D2). Already disclosed in-app at `GeneralSettingsView.swift:86-88` |
| Loox Link / Quick View | Encrypted snapshot served from Cloudflare for up to **30 days**; the content key lives in the URL fragment and never reaches the server |
| Relay email aliases | A server-side principal bound to a **verified destination inbox** — a real email address |
| Entitlement service | App Store subscription state keyed by an app-generated pseudonymous `appAccountToken` UUID |
| Breach check | k-anonymity prefixes only |
| App Attest | Device attestation for relay and Quick View |
| Cloudflare | Edge logs for every worker request |

### Required sections

Privacy: scope and controller; what is stored on device; what reaches Apple/CloudKit and
in what form; each named processor (Apple, Google, Cloudflare) and why; analytics and
crash defaults matching D1 exactly; the favicon disclosure; sharing surfaces and their
retention (Quick Link TTL per OPEN-5); relay destination-inbox handling; subscription and
billing data; legal bases; retention periods; user rights and how to exercise them; no
children's data; international transfers; changes and contact.

Terms: license grant; subscription products, prices, renewal, trial, grace period and
cancellation via Apple; Apple's standard EULA acknowledgement; acceptable use; the
no-recovery reality of a lost master password; disclaimers and liability limits;
termination; governing law (OPEN-3).

Security: correct `:19` to name the actual plaintext CloudKit fields rather than implying
everything is sealed; describe the key hierarchy, Extra Password/L2, Argon2id parameters,
and the sharing model honestly.

Delete every "starter template" blockquote and bump `lastUpdated` in the frontmatter.

The placeholder pages are currently marked indexable and the two locales are not
cross-linked with hreflang — fix both in `layout.tsx` / the policies page.

**Owner and counsel sign off before merge.**

---

## Agent 1C — iOS purchase surfaces

**Owns:** `VaultifyCore/Subscription/LooxMembership.swift`,
`Vaultify/Features/Subscription/LooxPaywallScreen.swift`,
`Vaultify/Features/Subscription/LooxAcquisitionPaywallView.swift`,
`Vaultify/Services/Subscription/LooxEntitlementStore.swift`,
new `VaultifyTests/LooxMembershipTests.swift`.

1. Repoint `termsURL` / `privacyURL` at `https://looxpassword.com/policies/terms` and
   `/policies/privacy`. Consider a locale-aware builder — the site serves `/vi/policies/*`
   and the app has a language toggle.
2. **M7:** add `.subscriptionStorePolicyDestination` (terms and privacy) to the
   `SubscriptionStoreView` at `LooxPaywallScreen.swift:113`. `subscriptionStorePolicy*`
   appears nowhere in the repo today, so 3.1.2 is not closed by fixing the constants alone.
3. Localize the two bare `Link("Terms of Use")` / `Link("Privacy Policy")` literals —
   write the keys to the staging strings file, not the catalog.
4. Add `LooxMembershipTests` pinning the URL shape so a future edit cannot silently
   reintroduce a dead link. Run `tuist generate` after adding the file.
5. Add an explicit `LooxMembership.betaPreviewEnabled` gate in front of
   `betaPurchaseAccess` (`LooxEntitlementStore.swift:47-53`) so a submission **can** ship
   with no commerce surface at all. D3 keeps commerce on, but today there is no switch —
   that is a gap worth closing regardless.

**Acceptance:** both links resolve 200 from a Release build in the review environment;
both purchase surfaces expose terms and privacy; no hardcoded price or period anywhere
(verified clean — everything loads from `Product.products`).

---

## Agent 1D — sole owner of `Project.swift` and both privacy manifests

**Owns:** `Project.swift`, `Vaultify/Resources/PrivacyInfo.xcprivacy`, new
`ExtensionResources/PrivacyInfo.xcprivacy`, new
`scripts/ci/check-privacy-manifests.sh`, `Makefile`.

Nobody else opens `Project.swift` in this phase.

1. **App manifest** — append a second `NSPrivacyAccessedAPITypes` dict:
   `NSPrivacyAccessedAPICategorySystemBootTime` / `35F9.1`. Sole use is
   `Haptics.swift:62` (`ProcessInfo.processInfo.systemUptime`, compared against a local
   `lastTick` and discarded), which matches `35F9.1` verbatim. Repo-wide sweep for
   `systemUptime|mach_absolute_time|CACurrentMediaTime|uptimeNanoseconds` returns this
   single hit, in the app target only.
2. Add `1C8F.1` alongside `CA92.1` in the existing UserDefaults reasons array. Both are
   needed: `SharedConfig.swift:27` and `ThemeReader.swift:12` use the App Group suite,
   while `ThemeReader.swift:35` reads `UserDefaults.standard`.
3. **NEW-1:** add `NSPrivacyCollectedDataTypeDeviceID`. `GoogleAppMeasurement` ships as a
   **static** archive with no manifest of its own, so its collection lands on the app's
   manifest, and `strings` shows `identifierForVendor` ×4. The app collects a device ID
   and declares none — for a password manager that is worse than a wrong reason code.
4. **Do not add `NSPrivacyCollectedDataTypeBrowsingHistory` for the favicon lookup.**
   Apple's "collected" definition covers data retained by you or your partners; a plain
   HTTPS GET to a public Google endpoint with no SDK and no data flowing back is genuinely
   gray, and "Browsing History" on a password manager's nutrition label is permanent,
   screenshot-able brand damage. Fix the mechanical leaks (Agent 2C) and the false in-app
   and README claims instead.
5. **New `ExtensionResources/PrivacyInfo.xcprivacy`** — a new top-level directory, outside
   every source glob. `NSPrivacyTracking = false`, empty tracking domains, **empty**
   `NSPrivacyCollectedDataTypes` (the appexes link no Firebase), UserDefaults with
   `[CA92.1, 1C8F.1]`. No SystemBootTime — no appex references it.

   Do **not** reuse the app manifest: it would ship Firebase's collection declarations
   into three bundles that collect nothing, which is a false declaration.
   Do **not** put it in `VaultifyCore/` — that path is inside the `VaultifyCore/**` glob
   used by all four targets.

   Wire it into the resources arrays of **all three** appexes: `VaultifyAutoFill`
   (`:225-232`), `VaultifyAutoFillMac` (`:288-293`), `VaultifySafari` (`:337-355`).
   The audit named only two; there are three, and the Mac one ships in the Mac slice.

   **Count precisely, the two numbers are different.** The *source* has four targets that
   need checking once `VaultifyAutoFillMac` is included. The *signed iOS IPA for this
   submission* contains exactly **three** executable bundles: `Vaultify.app`,
   `VaultifyAutoFill.appex`, `VaultifySafari.appex`. Apple requires a manifest in the
   bundle of every executable that uses a required-reason API, so the iOS acceptance
   criterion is three, and the fourth is covered only because it shares the same manifest
   file. Do not write "all four executables" when describing the iOS archive.
6. `defaultKnownRegions` — add `ja` (`Project.swift:18`). Confirmed to have zero shipping
   effect (String Catalogs ignore it; `ja.lproj` is already in the app and both appexes),
   so take it while in the file, do not schedule it separately.
7. iPad orientation contract per OPEN-1 — either add the `~ipad` four-orientation list, or
   narrow `TARGETED_DEVICE_FAMILY` to `"1"` and match the appex families.
8. **`scripts/ci/check-privacy-manifests.sh`** — keep it to roughly 40 lines: grep the
   required-reason API patterns across `Vaultify/`, `VaultifyCore/`, `VaultifyAutoFill/`,
   `VaultifySafari/`; `plutil -extract` the declared categories from the two manifests;
   fail naming the missing category. Hardcode the four-target mapping in a comment. Do not
   build a glob-resolution engine in bash for four targets.

**Exit:** `tuist generate` run; the new manifest present in all three appex bundles in a
built product; `check-privacy-manifests.sh` green.

---

## Agent 1E — in-app honesty copy

**Owns:** `Vaultify/Features/Settings/AboutView.swift`, `GeneralSettingsView.swift`,
`MacSettingsView.swift`, `SecuritySettingsView.swift`.

**Depends on D1 being frozen** — the honest string differs by default.

1. **M5:** `AboutView.swift:175` ships "Loox collects no analytics and has no accounts" in
   EN/VI/JA. Retire it. After D1 the truthful version is: analytics off unless you turn it
   on, crash diagnostics on and switchable off, no accounts.
2. `AboutView.swift:159-160` — "Zero backend / Nothing is sent to a server" is false
   (CloudKit, relay, Loox Link, Quick View, entitlement, favicon). Reword to the defensible
   claim: the vault itself is never readable by anyone else, and name the services that do
   use the network.
3. **Add Terms and Privacy links to the About privacy card.** Today `termsURL`/`privacyURL`
   appear on exactly one screen — a user who never opens the paywall has no in-app path to
   the privacy policy at all.
4. Split the breach-check disclosure from the favicon footer on both platform panes; the
   breach copy is wrong on macOS and absent on the iOS Security pane.
5. Keep the existing favicon footer — it names Google explicitly and is already translated
   to vi and ja. It is better disclosure than most commercial password managers ship; the
   defensible criticism is default-ON without an onboarding choice, not concealment.

All new strings go to `reports/strings-1e.json` (EN + VI + JA), not the catalog.

---

## Integrator — end of phase

Merge every `reports/strings-*.json` into `Vaultify/Localizable.xcstrings`, verify EN + VI
+ JA on every new key, then `tuist generate && make check`.

## Phase exit criteria

- [ ] `/terms`, `/privacy`, `/security` 308 to `/policies/*` in both locales; canonicals 200
- [ ] `routes-gate.sh` and the widened `claims-gate.sh` both green and wired into deploy
- [ ] No "starter template" text live; policies signed off by owner + counsel
- [ ] `home-compare` row 7 and every false claim in `messages/*.json` corrected
- [ ] Both iOS purchase surfaces expose working Terms and Privacy links
- [ ] `PrivacyInfo.xcprivacy` present and correct in each of the three executable bundles
      the iOS IPA contains, and in the Mac appex for when that slice ships; CI check green
- [ ] `AboutView` copy matches the shipping defaults; About links to both policies
- [ ] `tuist generate && make check` green
