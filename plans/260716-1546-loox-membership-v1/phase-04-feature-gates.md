# Phase 4 — Contextual feature gates

**Status 260716:** `LooxGate` + `LooxGateTests` done. Wired: persona create
(`PersonaSwitcherScreen.attemptCreate`), alias create both flows
(`PersonaAliasesScreen.guardQuota`), Loox Link create (`QuickLinkView`
createButton), Quick View approve pre-Face-ID (`QuickViewApprovalSheet`),
Watchtower paid surfaces (`WatchtowerScreen.openCategory` — fullReport /
fixQueue / history / historyDetail). **Deferred to pre-flag-flip QA** (all
inert while the flag is off): (a) outgoing-recipient seat — the share-ceremony
start has no single obvious choke point; scout `ShareSpaceSheet` + item-detail
share entry and gate where a NEW recipient ceremony begins, honoring the
same-person-never-consumes-a-seat rule; (b) themes — the accent picker flow
(`ThemeStore.setAccent`) plus §8.3 stored-preference preservation on downgrade.

**Goal:** §5.3 contextual paywalls — a gate only fires at a concrete over-quota
*create* action or a paid *view*, after value is visible. Client-side UX affordance
only in V1 (backend enforcement is the later authority, §7.1/§10.2). Entirely inert
while `LooxMembership.purchasesEnabled == false`.

**Hard rules (proposal §2, §5.3):** never gate vault ownership (read/copy/AutoFill/
backup/import/export/recovery), never limit stored item counts, never fire during
outage/destructive/recovery flows, never right after a security warning, never for an
already-entitled action. Gate failure must never delete or modify data (§2.6).

## Files

### Create — `VaultifyCore/Subscription/LooxGate.swift` (nonisolated, pure)
- `enum Allowance { case allowed; case needsUpgrade(to: LooxTier) }`
- Pure checks taking `(tier, currentCount)` and reading `LooxQuotas`:
  `canCreatePersona`, `canCreateAlias`, `canCreateLink`, `canApproveQuickView`,
  `canAddOutgoingRecipient`; plus `fullWatchtower(tier)`, `fullThemes(tier)`.
- `needsUpgrade(to:)` names the cheapest sufficient tier (recipient #2 ⇒ Max;
  alias #2 ⇒ Plus) so the paywall context is honest.
- Flag OFF ⇒ call sites simply don't consult the gate (checks stay pure/testable).

### Modify — call sites (scout exact functions at impl; one commit per surface)
| Surface | Gate point | Current count source |
|---|---|---|
| Personas | create-persona action (Personas feature) | `env.repository` personas |
| Private Email | create-alias action (`PersonaAliasesScreen` flow) | alias records |
| Loox Link | link creation entry (`LooxLinkService` UI caller, `QuickLinkView`) | `LooxLinkRecordStore` rolling 30d |
| Quick View | approve action (`ApprovalRequestSheet` / QuickView approve flow) | `QuickViewHistoryStore` rolling 30d |
| Approval sharing | add-recipient ceremony start (`ShareSpaceSheet` / invite flows) | distinct active recipients |
| Watchtower | full findings/history/Fix Queue sections | tier only |
| Themes | accent presets beyond free subset (`AccentColor` picker in Settings) | tier only |

- Gate UI: one shared sheet presenting `LooxPaywallScreen(context:)`. The blocked
  action stays visible with what it does; copy explains the plan that includes it —
  no loss-framing (§0 "Copy… không nói về cái bẫy").
- Watchtower Free floor: Critical/High findings + affected items always visible
  (§2.3 / §3.1) — gate only full findings list, history/diff, Fix Queue, reminders.
- Themes: free subset blue/graphite/mono (plan.md open Q2); paid accents render in the
  picker with a small Loox mark, tap ⇒ context paywall; a previously-chosen paid
  accent NEVER reverts destructively on downgrade — falls back to render-as-blue while
  preserving the stored preference (§8.3 "Paid visual preference được giữ").

## Tests (`VaultifyTests/LooxGateTests.swift`)
- Table-driven: every gate × every tier × boundary counts (at-quota, over, under;
  recipient 0-quota free case; personas nil-quota max case).
- Downgrade preservation: stored accent survives `fullThemes == false` (pure
  ThemeStore-level test if reachable; else document manual check).

## Validation
- `make check`; with flag ON in DEBUG + tier override: walk each surface at-quota and
  verify the sheet fires exactly at the §5.3 moment (after value visible, on the
  create action) and NEVER for entitled tiers.
- Regression: flag OFF ⇒ zero behavior change anywhere (diff-level certainty).

## Risks / notes
- Highest-touch phase (7 surfaces). Keep each gate a 3–5 line insertion calling the
  shared helper; no logic duplication in views.
- Rolling-30d client counts can undercount across devices — acceptable for V1 UX
  (server is later authority); never show "N remaining" as a promise, use the §3.2
  definitions for what counts (created-success / approved-success only).
