# Phase 2 — Membership hub redesign (iCloud+ vibe)

**Goal:** replace `LooxHubScreen`'s plain row list with an iCloud+-style membership
screen: tier header + circular member seal on the right, usage-aware feature grid,
plan section. This is the owner's focal ask (260716, screenshot: iOS Settings iCloud+).

**Context:** current screen `Vaultify/Features/Profile/LooxHubScreen.swift` (Private
Email row → `PersonaAliasesScreen`, Share Links row → `NotificationsScreen`, Approval
Mode toggle bound to `settings.approvalModeEnabled` with confirm-off dialog — behavior
must survive). Entry point stays `ProfileScreen.swift:48`
(`ProfileNavRow(title: "Loox", tile: .brandMark)`). Component library:
`ProfileComponents.swift` (`ProfileGroupCard`, `ProfileNavRow`, `ProfileRowDivider`,
`ProfileRowTile`). Brand art: `BrandSymbol` asset (see
`DesignSystem/Components/BrandLockup.swift`). Icons: **Polaris only** — the SF Symbol
exception (260715) is scoped to the Profile screen itself, not screens it pushes.

## iCloud+ anatomy → Loox mapping (from owner's screenshot)

| iCloud+ | Loox hub |
|---|---|
| Big title "iCloud+" + gray subscriber name | Tier `displayName` ("Loox" / "Loox+" / "Loox Max") + gray persona/identity display name (reuse `ProfileScreen.displayName` logic) |
| Circular seal top-right: cloud logo, curved ring text "NGƯỜI ĐĂNG KÝ • ICLOUD" | `LooxMemberSeal`: `BrandSymbol` center, curved ring text EN "LOOX • MEMBER •" / VI "THÀNH VIÊN • LOOX •" |
| Storage bar card | (skip — no storage concept; YAGNI) |
| "Saved to iCloud" 2-col tile grid with live metrics ("Mật khẩu · 53 mục") | "Included with your plan" 2-col grid with live local counts |
| "iCloud+ features" grid (Manage plan, Family…) | Plan section: paid → current plan + Manage subscription; free → upgrade card (flag-gated) |

## Files

### Create — `Vaultify/Features/Profile/LooxMemberSeal.swift`
- Circular badge ~64–72pt: `BrandSymbol` centered (~50% of diameter), ring text drawn
  as per-character rotation around the circle (uppercase, caption-size, wide tracking,
  `themedForeground(.secondary)`; paid tiers tint ring `accentText`).
- Localized ring string via `appString()` (EN/VI above; separators are `•` glyphs in
  the DECORATIVE ring only — the "no · separators" copy rule governs sentence copy, and
  the seal is `accessibilityHidden(true)` decoration, mirroring Apple's own seal).
- Static (no motion) ⇒ Reduce Motion is a no-op. Fixed frame, exempt from Dynamic Type
  (decorative; the header title carries the information).

### Create — `Vaultify/Features/Profile/LooxFeatureTile.swift`
- Grid tile: Polaris icon in a small tile (reuse `ProfileRowTile.polaris` look), title,
  metric line (`.subhead`, secondary). NavigationLink wrapper, min 44pt, pressed state
  per design DNA. Grid: `LazyVGrid` 2 columns, `Space.s3` spacing, inside a
  `ProfileGroupCard`-style surface or as separate mini-cards (match iCloud+: separate
  rounded tiles on the grouped background — pick after trying both in light+dark).

### Rewrite — `Vaultify/Features/Profile/LooxHubScreen.swift`
Layout (ScrollView, `Space.gutter` padding, grouped background, EMPTY inline nav title
— big title lives in content like iCloud+):
1. **Header**: leading VStack — `Text(tier.displayName)` `.vaultType(.largeTitle)`
   primary; `Text(displayName)` same type class, `.secondary`. Trailing:
   `LooxMemberSeal`.
2. **Plan section** (`LooxMembership.purchasesEnabled` gated):
   - paid: `ProfileGroupCard` rows — "Gói của bạn" value = tier name; "Manage
     subscription" → `.manageSubscriptionsSheet(isPresented:)`; "Change plan" → paywall
     (phase 3).
   - free: single upgrade card (short value prop + chevron) → paywall. Flag OFF ⇒
     section absent entirely (no dead CTA).
3. **Feature grid** — section label "Included with your plan" (EN) / VI equivalent:

| Tile | Metric (display-only, local) | Source | Destination |
|---|---|---|---|
| Private Email | "1 of 10 aliases" (used / `quotas.retainedAliases`) | alias records for active persona (via `PersonaAliasesScreen`'s data source — scout exact store at impl) | `PersonaAliasesScreen` |
| Share Links | count created in rolling 30d / quota | `env` LooxLink records (`LooxLinkRecordStore.records`, filter `createdAt` ≥ now−30d) | `NotificationsScreen` |
| Quick View | approvals in rolling 30d / quota | `env.quickViewHistory` entries (approved only) | `NotificationsScreen` (default; see plan.md open Q3) |
| Profiles (Personas) | "2 of 3" | `env.repository` personas count | persona management screen |
| Shared with people | "1 of 1" outgoing recipients | `env.sharingStore` / approval services distinct active recipients | `FamilyScreen` |
| Watchtower | "Full" / "Essentials" per `quotas.fullWatchtower` | tier | Watchtower screen |

   Denominators come from `LooxQuotas` — never hardcode numbers in the view. Max
   personas quota nil ⇒ show plain count (no "of ∞").
4. **Approval Mode card** — keep existing toggle + confirm-off dialog verbatim (single
   source `settings.approvalModeEnabled`).

### Modify — `Localizable.xcstrings`
Every new string EN + VI (tier names "Loox"/"Loox+"/"Loox Max" stay verbatim brand
terms — still add catalog entries with identical EN/VI). Metric formats use
localized plurals ("%lld of %lld aliases").

## Validation
- `make check`; light/dark, RT/RM, increased contrast, Dynamic Type (header wraps,
  seal fixed), VI longest labels (design for VI first per DNA doc).
- Behavior parity: Private Email, Share Links, Approval Mode toggle (+ confirmation)
  all still reachable and functional.
- DEBUG tier override: Free/Plus/Max flips title, seal tint, denominators live.

## Risks / notes
- Usage counts must never block render (async `.task` load like `ProfileDevicesCard`;
  show tile titles immediately, metrics fill in).
- Rolling-30d counts are client approximations for display (§7.1 backend counters are
  authoritative later) — phrase as plain counts, avoid "remaining" language.
- Persona scoping: alias count scopes to ACTIVE persona (INV-R03); quota is per
  subscription identity — display the persona-scoped count with wording that doesn't
  claim global truth (e.g. "aliases in this profile") until backend counters exist.
