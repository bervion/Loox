# Profile Refactor — Apple-Account-style hub

Status: **Planned** (awaiting go-ahead to implement)
Design refs: user mockup (Apple Account); prior spec `plans/260710-2135-loox-ui-ux-redesign/research/design-spec-settings-autofill-profile.md` §6c (Profile) + §5c (device list); `docs/design-guidelines.md`; `docs/design-dna-standard.md`.

## Goal
Restructure `ProfileScreen` from stacked cards into a grouped, nav-row hub (Apple-Account style): header (avatar + name + email), three grouped sections that route to detail screens, and a bottom "Switch profile" button. Consolidate Loox features; add Family (full group) and Devices (CloudKit registry).

## Target layout
- **Header** — avatar (+ camera badge) · name · email (name/email are new under the avatar).
- **Group 1** — `Personal Information` → identity detail (+ switch identity item); `Payment` → cards list.
- **Group 2** — `Loox` → hub (Private Email · Share links · Approval Mode); `Family` → family group.
- **Group 3** — `Devices` → device list (CloudKit registry).
- **Bottom** — `Switch profile` → persona switcher.

## Phases
| # | Phase | Type | Depends |
|---|-------|------|---------|
| 01 | Profile shell + nav restructure | reuse | — |
| 02 | Personal Information detail | reuse | 01 |
| 03 | Payment cards list (+ persona-scope fix) | reuse + **bugfix** | 01 |
| 04 | Loox hub | reuse consolidation | 01 |
| 05 | Family (full group) | net-new (large) | 01, ADR-F |
| 06 | Devices (CloudKit registry) | net-new (large) | 01, ADR-D |

Order: **01 first**. **02 / 03 / 04** are independent and parallelizable after 01 (they ship visible value fast). **05 / 06** are large net-new epics with their own ADR — sequence after the reuse phases; 01 links to them with an interim state until built.

## ADRs
### ADR-D — Devices data source: CloudKit device registry (chosen by user)
Each device upserts a private-zone CloudKit `Device` record { stable deviceID (Keychain UUID), name, model, lastSeenAt, appVersion }. Profile lists all: "This device" = Active, others = "Synced Xh ago" (from lastSeenAt). Publish on unlock + after successful sync. No PII beyond device name (already used by `ApprovalRecipientService`).
- **Revoke is security-critical.** True revoke = rotate the vault key + re-provision to remaining devices (heavy). MVP: "Remove device" deletes the record and stops recognizing it; full key-rotation revoke is a follow-up. **Must not weaken "Vault Key never syncs."** Finalize the MVP boundary in the Phase 06 ADR.
- Only meaningful when iCloud sync is on.

### ADR-F — Family: full family group (chosen by user)
Introduce a `FamilyGroup` (owner + members + invite/active status) and a group sharing target (share a Space / item set to all members), beyond today's per-item `ItemShareRecord`. Build over existing CKShare/Approval primitives.
- Product- and security-heavy. Phase 05 delivers the ADR + a **first slice** (group + member list over existing shares), NOT the full invite/shared-space in one shot. Recommend a dedicated design pass + `/ak:security` threat review before coding.
- Must respect ADR-2 (`approvalModeEnabled` ≠ vault sync) and persona isolation (whose items can be shared).

## Cross-cutting requirements
- **Persona isolation (INV-R03)** — every surface uses `items(for: persona)` / `activePersonaItems`. **Fix the current unscoped payment query** (Phase 03).
- **Navigation** — `ProfileScreen` is navigator-pushed (compact iOS UIKit shell); its new sub-screens push via ordinary SwiftUI (tab bar already covered) — no navigator wiring, no tab-bar-hide jank.
- **Design system** — grouped cards, tokens only, Polaris icons, `.elevation`, no hardcoded constants; verify light/dark + Reduce Motion/Transparency + 44pt targets.
- **Localization** — every new string EN + VI in `Localizable.xcstrings`.
- **Copy style** — no "!", no "—", no "·" as separator (design DNA).

## Acceptance (per phase)
- `make check` green (app + embedded extension).
- No persona leakage — an anonymous persona's cards / identities / aliases never appear under another profile.
- New strings localized EN + VI.
- Visual pass: light + dark + Reduce Motion/Transparency.

## Risks
- Payment persona-scope bug is **live today** — Phase 03 fixes a real privacy leak.
- Devices revoke touches vault-key crypto — scope the MVP carefully; do not break key-never-syncs.
- Family full group is large and under-specified — needs its own design; guard scope creep.
- Loox consolidation must keep a **single source of truth** for the Approval Mode flag (don't duplicate the toggle).

## Open questions
- Devices: exact revoke semantics for the MVP (delete record only vs. key rotation) — resolve in Phase 06 ADR.
- Family: full design (invite flow, shared-space model, permissions) — dedicated design pass.
- Payment: keep a per-persona "default card" marker, or a plain list? (`selectedPaymentCardId` is device-local today.)
