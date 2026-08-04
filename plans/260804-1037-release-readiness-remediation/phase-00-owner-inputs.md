# Phase 0 — Owner decisions and inputs

**Not agent work.** Everything here blocks a downstream phase. Recorded so the blocking
relationship is explicit rather than discovered mid-implementation.

## Already decided (2026-08-04)

D1–D7 are recorded in `plan.md`. No further input needed on those.

## Still needed

### OPEN-1 — Does iPad ship in v1?

D4 chose full multitasking support. Verification then surfaced two facts that were not
part of that decision:

- **iPad 13" screenshots are mandatory** for any submission declaring
  `TARGETED_DEVICE_FAMILY = "1,2"` (`Project.swift:173`). None exist anywhere;
  `fastlane/Fastfile:135` sets `skip_screenshots: true`.
- The iPad shell carries four verified defects on exactly the surfaces you would be
  screenshotting: sidebar search that cannot be cleared, editor drafts wiped on resize,
  nav bar hidden with no host on iPadOS 26, and a dropped first keystroke.

**Branch A — keep iPad (current decision).** Phase 6 stays on the critical path and an
iPad screenshot session is owed in Phase 7.

**Branch B — iPhone-only for v1.** Set `TARGETED_DEVICE_FAMILY = "1"`, narrow the appex
families to match, drop `.iPad` from destinations. Removes Phase 6's iPad track and the
screenshot requirement. Ship iPad in a later release with real QA.

**Mandatory in both branches:** M13 (`AdaptiveRootView` routing Plus/Max-class iPhones in
landscape into the iPad sidebar shell) is an **iPhone** bug. Lowering the device family
does not change `horizontalSizeClass` on an iPhone 16 Pro Max in landscape.

### OPEN-2 — Emergency Kit semantics with iCloud sync off — PROPOSED CONTRACT

Blocks Phase 2D entirely. `pushRecoveryEnvelopeIfNeeded()` is gated on
`iCloudSyncEnabled` (`SyncCoordinator.swift:90`). If the consent step leaves sync off:

- the Emergency Kit PDF's printed restore instructions ("sign into the same iCloud,
  scan the Setup Code") become false, and
- `JoinByRecoveryView` dead-ends on `.noEnvelope`.

The second reviewer supplied a specific contract, adopted here pending owner
acknowledgement. It is precise enough to implement against:

- iCloud sync defaults **OFF**, with no preselected option.
- The Emergency Kit is still generated when sync is off.
- With sync off, the Kit resets the **master password only**, and only while the vault and
  key bundle still exist on this installation.
- The Kit is **not an offline backup**. It does not survive device loss, app deletion, or
  a new device setup.
- Cross-device and device-loss recovery work **only** if sync was on and the recovery
  envelope uploaded successfully **before** the incident.
- When the user turns sync on, the UI must **await the first recovery-envelope push** and
  show success or failure. Silent best-effort is what created this ambiguity.
- Onboarding copy, the printed PDF, and Join-by-Recovery must all be corrected to this
  contract. Stop making the general claim that holding the Kit is enough to recover.

This is a genuine reduction in what the product currently implies. Owner should confirm
before Phase 2D writes the copy.

### OPEN-3 — Legal inputs for the Terms rewrite

Blocks Phase 1B. Nothing in either repo names them.

- Legal entity name and registered address
- Governing law and jurisdiction
- Consumer-rights/withdrawal position for the EU/VN markets you list
- Named data-protection contact (the policy currently says `privacy@looxpassword.com` —
  confirm that mailbox is monitored)

### OPEN-4 — Does the `ja` App Store localization ship in v1?

`metadata/apple/ja/release_notes.txt` exists, so someone intends it, but there is no
Japanese description or keywords anywhere.

If yes: point the ja listing's Privacy Policy URL at the English `/policies/privacy` —
Apple accepts one URL across localizations. You still owe Japanese description and
keywords in ASC. **Do not build `src/messages/ja.json`**; it is L-effort and off the
critical path.

### OPEN-5 — Is the Loox Link cleanup cron live in production?

`docs/fe-cloudflare-spec.md:42` marks it maintenance-only. The privacy policy's
retention clause depends on the answer, and so does M8's 30-day blast radius.

## Owner actions to take today

### M16 — Regenerate the AutoFill profile (four steps, not one)

An earlier draft of this plan said "run `make certificates`, it settles this in sixty
seconds". **That is wrong.** `make certificates` calls
`fastlane certificates` → `match(type: "appstore", readonly: true, …)`
(`fastlane/Fastfile:69-72`). Readonly **cannot create or update** a profile, so it will
report the stale profile rather than fix it.

The AutoFill entitlements now request iCloud/CloudKit and carry an in-file TODO to enable
that capability on `com.bervion.vaultify.autofill`. Correct sequence:

1. Enable the CloudKit capability on the AutoFill App ID in the Developer portal.
2. A maintainer with write access runs `match` in write/force mode to regenerate the
   profile and store it in the certificates repo. This is deliberately not a `make` target.
3. Then run `make certificates` (readonly) to verify the release runner resolves the new
   profile.
4. Then produce a signed archive and inspect the entitlements of the app and **both**
   embedded extensions.

Skipping step 2 means a tagged release dies at the signing step with a stale profile.

### M3 — Decide "Mac (Designed for iPad)" availability

Because iPad is a supported family, App Store Connect offers and **defaults to enabling**
this. macOS does not surface an iPad app's AutoFill credential provider, so a Mac user who
installs it gets a password manager whose AutoFill silently never works. There is no macOS
lane in `fastlane/Fastfile` — the native Mac slice is not being submitted this round.

Uncheck it in ASC, or ship the native Mac slice with its own lane. Two clicks; getting it
wrong produces 1-star reviews rather than a rejection.

### M18 — Confirm Google Signals is OFF in the GA4 property console

If anyone enables it, GA4 data becomes usable for advertising, "not used for tracking"
becomes a false answer on the App Privacy questionnaire, and an ATT prompt is owed with no
code to show it. Console setting, outside both repos, invisible to any audit of the code.

### M17 — Export compliance position

`Project.swift:67` sets `ITSAppUsesNonExemptEncryption = false`, justified in a comment as
"standard algorithms protecting the user's own on-device data". That is not one of Apple's
listed exemptions (authentication/signature only; OS-confined; medical; fixed data
compression; copy protection). The app ships a vendored third-party Argon2id and a full key
hierarchy providing **data confidentiality**.

This will not block the upload — Apple takes the flag at face value. But it is an answer to
a US export-control question, and the remedy for getting it wrong is app removal, not a
rejection email. The defensible position is `true` plus mass-market self-classification
(annual BIS report / ERN). **Owner + legal decision. Do not let an agent change it either
direction.**

### M14 pre-check — production host liveness

Release builds (TestFlight and App Review) use production constants. Only `api-relay` has a
health probe. Before submitting, curl each and record the result in Phase 7's evidence:

```
api.looxpassword.com            s.looxpassword.com
config.looxpassword.com/v1/capabilities
config.looxpassword.com/v1/domain-registry
config.looxpassword.com/v1/quick-view/signer-keyset
api-relay.looxpassword.com      entitlement.looxpassword.com
open.looxpassword.com
https://invite.looxpassword.com/.well-known/apple-app-site-association
```

The AASA must serve `application/json` with the correct team-prefixed appID.

Related: **App Attest behaves differently in sandbox vs production.** A prior in-repo audit
(`plans/reports/audit-260726-1152-attest-passkey-root-cause.md`) claims the token path is
dead in production. If attestation fails in the review environment, relay alias creation and
Quick View both break for the reviewer. Verify on a real TestFlight build.

## Exit criteria

- [ ] OPEN-1 through OPEN-5 answered and recorded in `plan.md`
- [ ] `make certificates` run green with the AutoFill iCloud capability enabled
- [ ] Mac availability decided
- [ ] Google Signals confirmed off
- [ ] Export compliance position recorded with rationale
- [ ] Production host + AASA probe results recorded in `reports/`
