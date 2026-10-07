---
date: 2026-10-07
session: loox-member-private-email-ux-plan
status: planned
---

# Loox Member and Private Email UX Plan

## Context

TestFlight 1.56.6 restored the user's Private Email flow. The follow-up exposed missing domain choices, masked recipients, stale verification state and confusing Member destinations. Scope today: analysis, implementation plan and local design preview.

## What happened

Production's signed registry includes `email-pw` for `loox.pw`, but its lifecycle is `createDisabled`. The picker is respecting that gate. D1 configuration and end-to-end mail readiness remain unproved.

Inbox detail masks the full recipient. Verification refresh misses some entry/foreground transitions and newly pending inboxes. Day's neutral banner shares the canvas color. Share Links and Send to Browser lead to Notifications; Family already has a share-derived screen, without an independent membership roster.

## Reflection

The difficulty is trust in state and navigation. A quieter interface helps only when it identifies the actual inbox, distinguishes verification from opening a browser, and exposes the next valid action.

## Decisions

The [implementation plan](/Users/bervion/Developer/Projects/mobile/ios/Vaultify/plans/261007-1825-loox-member-and-private-email-ux-overhaul/plan.md) keeps native navigation, semantic tokens, Polaris and Controlled Reveal. Service aliases permit optional Login links and labels. Deliberate navigation into unlocked InboxDetail reveals the local email; overview remains masked, conceal immediate. Each Member feature receives its own root while reusing existing security ceremonies.

Review gates cover stale asynchronous results, persona/identity ownership, verification for the current email, immutable issued domains, draft/activation checkpoints and fail-closed domain selection. Sharing controls remain independent of vault sync. Historical links cannot reconstruct missing fragments; Browser history cannot replay sessions; Family does not invent account roles.

## Next

Verify D1 policy and isolated staging API/schema behavior, then prove real production-apex mail delivery before domain activation and signed-registry promotion. Keep the production catch-all unchanged during staging checks. Implement recipient state before UI polish, then native localization/accessibility/device QA. Local HTML checks are preview evidence only; no app tests, deployment or production configuration changes were performed in this planning turn. AgentWiki publication skipped because external sharing was not requested.
