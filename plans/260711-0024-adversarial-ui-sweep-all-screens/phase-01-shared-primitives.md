# Phase 1 — Shared Primitives & Components

**Priority**: P1 (blocks W2) · **Status**: pending · **Parallel**: W1, alone.
**Owns**: `Vaultify/DesignSystem/Components/*`, `Vaultify/DesignSystem/PolarisIcon.swift`, `Vaultify/DesignSystem/Tokens/Elevation.swift`, `VaultifyCore/BrandLogoMark.swift`, `Vaultify/Features/Components/*`, `Vaultify/Features/Capabilities/CapabilityBannerView.swift`.

## Protagonist
These are the atoms every screen reuses. Fix them FIRST so all W2 phases treat them as frozen,
read-only, and correct. A defect here (e.g. a doubled copy haptic, a raw color, a non-token radius)
otherwise multiplies across the whole app.

## Surfaces (30)
Design-System components: `ThemedButtonStyles`, `ThemedComponents`, `ThemedToggleStyle`,
`VaultInfoBanner`, `VaultSheetScaffold`, `VaultScreenHeader`, `VaultStatusBadge`, `GlyphResolveText`,
`CopyMorphIcon`, `LooxGateShape`. Feature components: `CopyToastOverlay`, `RevealableSecureField`,
`ItemThumbnail`, `VaultComponents`, `PasswordStrengthMeter`, `FaviconView`, `SpoilerText`, `QRCodeView`.
Shared: `CapabilityBannerView`.

## The adversarial protocol (CANONICAL — every cluster phase references this)
For EACH surface, write the answers in `reports/findings-phase-01.md`; "it looks fine" is not an answer.
1. **Protagonist** — what is this component's one job? Does anything here compete with it?
2. **Every text** — read each string EN + VI aloud. Calm, honest, short? Any `!`, `—`, `·`? Does VI fit
   at SE width (375pt)?
3. **Every control** — thumb-hittable one-handed? Hit box ≥ `Metric.hitMin` (44)? Purpose obvious?
   Visual feedback + CORRECT haptic (vocabulary table)?
4. **Every space & shape** — each padding a `Space` token? Each radius from the scale or
   `Radius.concentric`? Nothing pinched/flared/floating?
5. **Every state** — empty / one / many / loading / error / locked-gated: does each look intentional,
   or does one expose scaffolding (duplicate sections, stranded rows, dead ends)?

### In-code audit gates (run over OWNED files)
```
grep -nE '\.font\(\.|\.font\(\.system'              # typography defects → vaultType / Font.vaultCode
grep -nE 'cornerRadius\(|RoundedRectangle\(cornerRadius'  # radius → token / concentric
grep -nE '\.padding\([0-9]'                         # numeric padding → Space.*
grep -nE '\.white|\.black|\.gray|\.red|\.primary|\.secondary'  # raw color → semantic role
grep -nE 'Haptics\.'                                # cross-check vocabulary table, no doubling
grep -nE '\.frame\(width:|GeometryReader|minimumScaleFactor|lineLimit\(1\)'  # SE-width / DT risk
```
- **Haptics vocabulary** (the law): Copy→`Haptics.success` fired by `ClipboardService` ONLY (a view
  must never add another); Destructive-confirm / auth-fail→`Haptics.error`; Risky-reveal→`Haptics.warning`;
  Selection/toggle→`Haptics.tap`; scroll/nav/appear→none. `CopyToastOverlay`/`RevealableSecureField`/
  `SpoilerText` are prime doubling-suspects — verify they do NOT fire a second haptic on copy/reveal.
- **Color exemptions** (allowed raw): camera/scanner surfaces, `QRCodeView`, `FaviconView` remote art,
  `EmergencyKitPDFPage` (always-light print), literal light↔dark preview swatches.
- **Multi-device**: `PasswordStrengthMeter` label + `VaultStatusBadge` + `VaultInfoBanner` carry the
  longest VI strings — verify no clip at SE, no truncation at Dynamic Type XL/AX-XXL.

## Deliverables
1. `reports/findings-phase-01.md` — findings table `component | Q(1-5) | finding | fix | severity | status`.
2. `strings-manifest-phase-01.md` — any new/changed strings `key | EN | VI | context`.
3. Fixes applied to OWNED files only.

## Todo
- [ ] Write protocol answers for all 30 surfaces.
- [ ] Run the 6 audit greps; log every hit as a finding row.
- [ ] Verify no doubled haptics in copy/reveal components.
- [ ] Fix defects; re-grep to confirm zero remaining in owned files.
- [ ] Emit strings manifest for orchestrator merge.

## Success criteria
- Zero audit-grep hits remain in owned files (outside documented exemptions).
- Every reused component passes SE + Pro Max + Dynamic Type XL + light/dark + Reduce Motion/Transparency.
- Copy/reveal haptics fire exactly once, from the service layer.

## Risk
| Risk | L×I | Mitigation |
|---|---|---|
| A W2 phase needs a component change mid-flight | Med×Med | It files `reports/shared-component-requests.md`; Phase 1 owner (or orchestrator) applies — never the W2 phase |
| Fixing a shared component shifts layout app-wide | Med×High | Change token/haptic, not geometry, where possible; note any geometry change for W2 phases to re-verify |
| `GlyphResolveText`/`LooxGateShape` motion regression | Low×Med | Preserve Reduce-Motion instant-swap path; do not alter timing outside `Motion` range |

## Next
Blocks all W2 phases (2–14). They must not edit any file in this phase's scope.
</content>
