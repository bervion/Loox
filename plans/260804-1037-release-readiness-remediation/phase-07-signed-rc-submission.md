# Phase 7 — Signed RC, App Store Connect, submission

Owner-led. Nothing here is a code change; everything here can lose a full review cycle.

---

## 7.1 — Independent red-team before cutting the RC

A reviewer who did **not** implement any of it re-reads:

- the privacy surface (manifests, in-app copy, policy pages, ASC answers) for internal
  consistency
- the crypto and data-migration changes from Phase 3
- the extension command boundary — `getFillPayload` must remain the only native→JS command
  that returns vault values, and no content-script-reachable command may summon Face ID
- the release workflow's same-SHA gate

## 7.2 — App Store Connect metadata (M2) — hard blocker

`metadata/apple/` contains exactly three files: `en-US/release_notes.txt`,
`ja/release_notes.txt`, `vi/release_notes.txt`. The `submit` lane passes
`skip_metadata: false, force: true`, so `deliver` would push an incomplete record with no
confirmation prompt. On a fresh app record that either errors or submits something Apple
rejects as incomplete.

Required for a first submission:

- [ ] App name, subtitle, description, promotional text, keywords
- [ ] Support URL, marketing URL, copyright
- [ ] Primary and secondary category
- [ ] Age rating questionnaire
- [ ] Privacy Policy URL (`https://looxpassword.com/policies/privacy`)
- [ ] App Review notes and contact (7.4)
- [ ] Per-locale copy for **`en-US` and `vi` only** on this submission

**Japanese: keep it in the binary, keep it out of the listing.** Continue translating every
new string to JA so the UI never mixes languages, but do not open a `ja` App Store
localization until there is a real description, subtitle, keywords, and a copy QA pass.
`metadata/apple/ja/` currently holds release notes with no listing copy behind them, and
`deliver` will happily push a half-populated localization. **Filter or move
`metadata/apple/ja` out of the deliver automation** until that copy exists.

Fix the `submit` lane to match, or drive metadata through ASC directly and set
`skip_metadata: true`.

## 7.3 — Screenshots (M1) — hard blocker if iPad ships

- [ ] iPhone 6.9"
- [ ] **iPad 13"** — mandatory while `TARGETED_DEVICE_FAMILY = "1,2"`. None exist;
      `Fastfile:135` sets `skip_screenshots: true`
- [ ] Capture only after Phase 6 lands — the iPad surfaces you would screenshot are exactly
      the ones with defects

If OPEN-1 chooses Branch B, drop the family to `"1"` and this row disappears.

## 7.4 — App Review notes (M4) — highest ROI item in this phase

Password managers are rejected under Guideline 2.1 for *"we could not locate the described
functionality"* more than for anything else, because the reviewer never enables the
credential provider. One hour of writing; an entire review cycle at stake.

Must cover:

1. **No account and no demo credentials are needed** — say this explicitly, reviewers look
   for a login screen. Get Started → master password → save the Emergency Kit → done.
2. The app seeds a default identity from the name and email entered during setup. It does
   **not** add a fake password credential.
3. To test a login: Add → Login, using the public test form at `[REVIEW TEST URL]` with any
   non-sensitive sample credentials.
4. **AutoFill:** Settings → General → AutoFill & Passwords → enable Loox, then demonstrate
   on any login form.
5. **Safari extension:** Settings → Apps → Safari → Extensions → Loox → enable → Allow on
   All Websites. Explain **why** `host_permissions: ["https://*/*"]` is required — credential
   field detection on arbitrary login pages — and that vault values are returned only through
   the gated fill command after an explicit user selection.
6. Which features need network (Loox Link, Quick View, relay aliases, breach check) and which
   are fully offline.
7. Face ID is optional; the master password always works.
8. iCloud vault sync is optional and stays off until explicitly enabled (must match what
   Phase 2D actually ships).
9. Subscription state: the paywall is live, and the four attached products are
   `[LIST PRODUCT IDS]`. Terms and Privacy resolve to `[FINAL URLS]`.
10. Reviewer contact name, email, phone.

Send it in English. Do not put a fixed master password or real credentials in the notes.

## 7.5 — App Privacy questionnaire — file last

Depends on D1, the Device ID declaration and D2 all being frozen in code. Must match the
privacy manifest, the policy page, and runtime behavior exactly. Confirm
`NSPrivacyTracking = false`, empty tracking domains, and Google Signals off (M18).

## 7.6 — Pre-submit gates

- [ ] **Production host liveness (M14)** — every host and path in
      `phase-00-owner-inputs.md`, plus the AASA at `invite.looxpassword.com` serving
      `application/json` with the correct team-prefixed appID. Record the results.
- [ ] **App Attest in the review environment** — if attestation fails, relay alias creation
      and Quick View both break for the reviewer. Verify on a real TestFlight build.
- [ ] **CloudKit production schema** — `docs/deployment-guide.md:138-155` lists the types and
      records that this "has already shipped past twice". Not listed there:
      `ArtifactRecord`/`ArtifactV2` (new in v1.50.0), the approval-share zone types, and
      `VaultKeyEnvelope`. Confirm every record type the shipping build can write exists in
      **Production**, and confirm `artifactSyncEnabled` is still `false` so `ArtifactV2`
      cannot be written before its schema deploy. Not a rejection risk — a
      total-feature-failure-on-day-one risk, which is worse.
- [ ] **Push subscriptions** — `APS_ENVIRONMENT` is correct (`development` Debug /
      `production` Release, verified in the generated pbxproj). CloudKit subscriptions
      registered against Development do not exist in Production; they self-heal at runtime,
      but only once the production schema exists. Folds into the previous gate.
- [ ] **v1.49.1 → RC upgrade** on a real device with a representative vault: unlock, read,
      edit, export, relaunch; verify items, passkeys, artifacts, folders, personas. Repeat
      under low storage.
- [ ] **Mac availability (M3)** decided and set in ASC.
- [ ] `make certificates` green (M16).

## 7.7 — Runtime QA matrix

| Matrix | Scenarios |
|---|---|
| iPhone SE 375, Pro Max 430 | Fresh install, restore, unlock, CRUD, import/export, lock/relaunch, live theme switch, **landscape on Pro Max** (M13) |
| iPad 11" / 13" (Branch A only) | Portrait, landscape, fullscreen, narrow and wide Split View, Stage Manager resize **with the editor open** (M12), hardware keyboard |
| iOS 17.3 | Password AutoFill + passkeys at the deployment floor |
| iOS 18 | OTP AutoFill, passkey upgrade paths |
| iOS 26.2+ | Save/generate credential capabilities, toolbar and accessibility rendering |
| Accessibility | AX XXXL, VoiceOver, Reduce Motion, Reduce Transparency, increased contrast |
| Security state | No biometric, Face ID changed / locked out, App Group unavailable, offline, iCloud signed out |
| Data | Empty vault, large vault, artifacts, L2 fields, archived/trashed, v1.49.1 upgrade |
| Sharing | Two Apple IDs and devices; accept and revoke online and offline; ask-each-time; push delay |
| Erase | Quick Link live + sharing on + airplane mode + kill immediately after tap; verify from a second device and a browser |
| Extensions | AutoFill and Safari on iPhone (and iPad, Branch A), large vault under memory pressure, lock/relock, concurrent access |
| Subscription | Sandbox purchase, restore, upgrade, downgrade, cancel; subscriber never sees the acquisition paywall; backend outage ≠ downgrade |

## 7.8 — Cut and ship

1. New tag at a version number the **owner** picks, build > 78. Do not assume `v1.51.0` —
   the current RC may already claim it. **Do not move or reuse `v1.50.0`.**
2. Signed archive from the exact tag SHA.
3. Xcode Validate / Transporter pass.
4. Inspect the IPA: app + iOS AutoFill + iOS Safari only, no Mac binary; version and build
   identical across all three; entitlements match the profiles; `PrivacyInfo.xcprivacy`
   present in every executable and the privacy report clean.
5. dSYM upload to Crashlytics succeeds with a receipt. Note this happens in the fastlane
   release lane, **not** an Xcode run-script phase.
6. `LooxLinkAppToken` production value non-empty. A missing value fails loudly on the CI
   release path but **silently on any non-CI archive** — verify explicitly. Never print it.
7. Owner signs the checklist. Submit.

## 7.9 — Do not do this round

- Do not create or submit a macOS App Store version.
- Do not enable wide external TestFlight testing on build 78.
