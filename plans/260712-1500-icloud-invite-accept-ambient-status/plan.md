---
title: "iCloud Approval-Mode: Ambient Invite → Accept → Status"
description: "Push-driven owner-side acceptance status (silent push + local notification), badge/copy fixes, request-scan perf, conflict-safe profile publish, recipient safety-code verify gate"
status: completed
priority: P1
effort: 13h
branch: main
tags: [approval-mode, cloudkit, push, sharing, security]
created: 2026-07-12
---

# iCloud Approval-Mode: Ambient Invite → Accept → Status

Source audit: `plans/reports/from-flow-audit-260712-1453-icloud-invite-accept-status-report.md`

**Goal:** owner A never has to sit in the app waiting for recipient B's acceptance. Silent CloudKit push on B's profile publish → background status refresh → local notification → tap lands on the resume stepper. Plus: honest copy, actionable bell badge, request-scan perf fix, conflict-safe multi-device profile publish, and a recipient-side safety-code verification gate replacing silent auto-TOFU.

## Phases

| # | Phase | Status | Depends on | Effort |
|---|-------|--------|-----------|--------|
| 1 | [Silent acceptance push subscription (R1)](phase-01-silent-acceptance-push-subscription.md) | completed | — | 2h |
| 2 | [Local notification + tap routing (R2)](phase-02-local-notification-and-tap-routing.md) | completed | 1 | 2.5h |
| 3 | [Copy, badge, sheet responsiveness (R3+R4+R7)](phase-03-copy-badge-and-sheet-responsiveness.md) | completed | 1 | 1.5h |
| 4 | [Request-scan perf: dirty flag (R5)](phase-04-request-scan-perf-dirty-flag.md) | completed | — | 1.5h |
| 5 | [Conflict-safe profile publish (R6)](phase-05-conflict-safe-profile-publish.md) | completed | — | 1.5h |
| 6 | [Recipient safety-code verify gate (S1)](phase-06-recipient-safety-code-verify-gate.md) | completed | — | 3h |
| 7 | [Tests + verification](phase-07-tests-and-verification.md) | completed | 1–6 | 1.5h |

> Local test caveat (2026-07-12): a pre-existing environmental host crash (verified at baseline commit 1c7e052) fails every UserDefaults-persisting test on this machine's Xcode 27 beta simulators — all suites added by this plan pass; the full suite must be confirmed green on the CI stable Xcode before merge. Device QA checklist lives in phase-07.

## Dependency graph

```
P1 ──> P2 ──┐
P1 ──> P3 ──┤
P4 ─────────┼──> P7
P5 ─────────┤
P6 ─────────┘
```

P4, P5, P6 are independent of P1–P3 and of each other (disjoint files). Recommended execution: sequential P1→P2→P3, then P4/P5/P6 in any order, P7 last. `Localizable.xcstrings` is touched by P2, P3, P6 — if run in parallel, xcstrings edits must be serialized (single owner).

## Key constraints (bake into every phase)

- Gate on `approvalModeEnabled`, NEVER `iCloudSyncEnabled` (ADR-2).
- No plan-artifact refs (R1/S1/phase numbers) in code, comments, commits, or filenames — explain the why.
- Every new user-facing string: EN + VI in `Vaultify/Localizable.xcstrings`. No "!", no "—", no "·".
- Polaris SVG icons only; token-driven design (`Space/Radius/Metric/.vaultType/.themedForeground`).
- Remote-notification background mode + `registerForRemoteNotifications` already in place (`Project.swift`, `AppPushDelegate.swift:20`) — no entitlement work.
- Compile check after each phase: `tuist generate --no-open` + workspace xcodebuild per CLAUDE.md (never the bare word "build" in bash).

## Out of scope / notes

- **R8 (cross-device share status):** deferred to the iPad/Mac multiplatform plan. `SharingStore` stays UserDefaults device-local; status can later be derived from CloudKit state (zone list + profile presence) with no new storage.
- **ApprovalSpike.swift removal:** verified — only referenced from the DEBUG-gated QA panel in `SyncSettingsView.swift:85-105` (`#if DEBUG`). Safe dead-code-removal candidate, but NOT part of this plan; do separately to keep diffs reviewable.
- **CKQuery for R5:** rejected in favor of dirty-flag (see phase 4) — a production CKQuery needs queryable indexes on the deployed CloudKit schema; the dirty-flag has zero schema risk.

## Success criteria (plan-level)

1. A backgrounds the app after inviting; when B accepts and unlocks, A gets a banner within seconds-to-minutes without opening the app; tapping it opens the resume stepper on that share.
2. Bell badge counts shares awaiting the ceremony.
3. Foregrounding the app with zero in-flight requests performs zero full-zone scans (after the cold-launch pass).
4. Two of B's devices publishing profiles concurrently both survive in the device directory.
5. B sees a safety-code verification step before first use of shared content; the pin is only trusted after explicit confirm or explicit skip.
6. `make test` green including new coverage; `make check` compiles app + extension.
