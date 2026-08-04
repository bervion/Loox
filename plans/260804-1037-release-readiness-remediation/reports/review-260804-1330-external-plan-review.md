# Second-reviewer pass on the remediation plan — disposition

- Date: 2026-08-04
- Reviewed at: `1405cc9 chore: update docs` (plan and reports only; no iOS or frontend source)
- Verdict retained: **NO-GO**
- This file records what was accepted, what was adjusted, and what goes back to the owner.
  The plan files themselves were edited; this is the audit trail for why.

## One premise was stale, and it matters for the record only

The review states the frontend is "chưa commit, chưa deploy". At the time `1405cc9` was
cut that was accurate, because the implementation report committed in it still said so.

Since then, Phase 1A and 1B were committed and **merged**:
[looxpassword-web PR #5](https://github.com/bervion/looxpassword-web/pull/5), merge commit
`a5d7965`, 17 files, +888/-176. `origin/main` and local `main` agree.

This does **not** change the verdict. Everything else the review lists as missing is still
missing: no independent review of the real diff, six legal placeholders unresolved, no
counsel sign-off, Quick Link cleanup cron unconfirmed, 1A.4 not done, and **nothing
deployed**. Merged is not shipped, and shipped is not verified. NO-GO stands.

The reviewer could not verify independently because they do not have that repository. That
is a real gap in the evidence chain, not a formality — the frontend needs a reviewer with
access before it is called done.

## Accepted, plan edited

| Point | What changed |
|---|---|
| Phase 1A/1B status wording | `plan.md` now states merged-but-not-deployed, not-independently-reviewed, and lists the six outstanding conditions |
| **1A.4 contact form not done** | Confirmed at `contact-form.tsx:29` — `setSent(true)` fires unconditionally. `phase-01` now marks it **NOT DONE** and calls out that the implementation report omitted it |
| `make certificates` cannot regenerate | Confirmed: `Fastfile:69-72` is `match(readonly: true)`. `phase-00` M16 replaced with the four-step portal → write-mode match → readonly verify → signed-archive-inspection sequence, and explicitly retracts the earlier "sixty seconds" line |
| `make test` scheme and destination | Confirmed `Makefile:14` `SCHEME := Vaultify` while `Vaultify-Quality.xcscheme` is the shared scheme carrying tests, and `Makefile:17` pins an unresolvable `name=iPhone 16`. `phase-04` rewritten, **including retracting this plan's own earlier advice** to use `generic/platform=iOS Simulator` for tests — generic is compile-only; tests need a discovered/created simulator UDID as CI does |
| Privacy manifest counting | `phase-01` and `plan.md` now distinguish four *source targets* to check from the **three executable bundles** the iOS IPA actually contains |
| Empty `VersionedSchema` | Accepted and reversed. `phase-03` no longer calls a bare scaffold "cheap insurance" — declaring a `VersionedSchema` where none existed changes how SwiftData resolves migration, so it is added risk without fixture tests. Pick implicit-plus-upgrade-test (recommended) or explicit-plus-fixtures, not a half measure |
| Erase failure semantics | `phase-02` now requires: retain enough revoke record/token to retry, **or** define the action as local-only erase and say so. Airplane-mode and kill-mid-erase repro made explicit |
| macOS must not block the iOS RC | Added as a scope note in `phase-02` — fix via the shared coordinator because it is the same path, but a macOS-only defect is not an iOS blocker |
| JA listing | `phase-07` now says keep JA in the binary and keep translating, ship the listing as `en-US` + `vi` only, and **filter `metadata/apple/ja` out of deliver automation** until real description/keywords/QA exist |
| Version naming | `v1.51.0` retired from the plan; it now says "the next release" until the owner picks a number |
| File ownership | `Makefile`, `fastlane/Fastfile`, `MacSettingsView.swift`, `VaultStore`/migrations added to the collision table, plus the four genuine serialization dependencies |
| Export compliance | No change needed — the plan already ruled this owner-plus-legal and forbade agents from touching it in either direction. Agreement recorded |

## Adjusted, because the evidence is machine-specific

**M15 — "stale, Xcode 26.5 (17F42) present and `select-xcode.sh` runs green".**

That is true on the reviewer's machine and false on the primary working machine, checked
today:

| Machine | Installed | `select-xcode.sh` |
|---|---|---|
| Primary working machine | `Xcode.app` **26.6**, `Xcode-beta.app` 27.0 | **fails**, exit 1 |
| Reviewer's machine | 26.5 (17F42) | passes |
| Self-hosted release runner | not verifiable from here | unknown |

The pin is exact string equality on `26.5`, so a patch bump to 26.6 breaks it. The finding
is therefore not withdrawn — but the reviewer's **reframing is adopted**, because the
disagreement itself proves the point: three machines, three answers, no inventory. `phase-04`
now describes it as a runner-inventory/preflight gate rather than "26.5 is installed
nowhere", and the original wording is corrected.

**Full `pnpm lint` and the deploy pipeline — question answered.**

`scripts/deploy-marketing.sh` runs `cf:deploy` → cache purge → gates. It never invokes
`lint` or `typecheck`, and neither `next.config.ts` nor `open-next.config.ts` configures
ESLint during compilation. **The marketing deploy is not gated on lint at all.** The 3
errors and 12 warnings live in `workers/loox-relay` and `workers/loox-quick-view`, which
this PR did not touch and which the marketing worker does not compile. They are worth
fixing, but they cannot block this deploy and they are not evidence about this change.

## Referred back to the owner — implementers may not decide these

Three review points recommend reversing decisions the owner already locked on 2026-08-04.
They are recorded in `plan.md` as contested with an explicit risk acceptance, and left as
the owner ruled them.

- **R1, favicon default ON.** Reviewer: default OFF; a password manager should not send a
  credential's hostname to Google to decorate a row. Owner decision D2 keeps it ON. Now
  recorded as a privacy-risk acceptance requiring legal and ASC privacy review, with the
  Phase 2C mechanical fixes promoted from optional to mandatory.
- **R2, `launchEnabled = true` at submission.** Reviewer: attaching the IAPs satisfies
  Apple's first-subscription rule by itself; a day-one paid launch on top of a first
  submission is separable risk. Owner decision D3 keeps the flip. Recorded in `phase-05`
  with §5.6's ordering as the mitigation.
- **OPEN-1, iPad in v1.** Reviewer: iPhone-only for a first submission. Owner decision D4
  keeps iPad. Recorded that if Branch A stands, Phases 6 and 7 may not be trimmed, and that
  M13 ships in both branches because it is an iPhone bug.

## Adopted as a contract — needs owner acknowledgement

The review supplied a precise Emergency Kit contract, which resolves OPEN-2 and unblocks
Phase 2D. It is written into `phase-00` verbatim in substance: sync OFF by default; the Kit
still generated; with sync off it resets the master password only and only while the vault
and key bundle survive on this installation; it is not an offline backup and does not
survive device loss, app deletion or a new device; cross-device recovery works only if sync
was on and the envelope uploaded before the incident; enabling sync must **await** the first
envelope push and show success or failure; onboarding, PDF and Join-by-Recovery all corrected.

This is a real reduction in what the product currently implies to users, so it needs an
explicit owner acknowledgement before Phase 2D writes the copy.

## Standing correction to this plan's own earlier drafts

Two things this plan previously asserted were wrong and are now fixed in place. Recorded
here so nobody restores them from an older read:

1. "Run `make certificates`, it settles this in sixty seconds." It cannot — the lane is
   readonly.
2. "Set `DEST` to `generic/platform=iOS Simulator`." Valid for a compile check, invalid for
   `xcodebuild test`.
