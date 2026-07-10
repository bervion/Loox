---
name: vaultify-adversarial-ui-sweep-plan
description: Plan 260711-0024 adversarial full-app UI/UX sweep — all 187 View structs reviewed against design-dna-standard, 16 phases, disjoint file ownership
metadata:
  type: project
---

Adversarial UI/UX sweep of ALL Vaultify screens against `docs/design-dna-standard.md` (acceptance bar).
Plan dir: `plans/260711-0024-adversarial-ui-sweep-all-screens/`.

**Why:** every screen (old+new) must pass the 10-DNA standard + multi-device matrix (SE 375 / Pro Max 430,
Dynamic Type, light/dark/7-accent, Reduce Motion/Transparency, EN+VI). Adversarial = reviewer WRITES protocol
answers per screen (protagonist/text/control/space/state) then fixes.

**How to apply:** 16 phases. P0 = screen registry (187 structs, unassigned=FAIL). P1 = shared primitives
(DesignSystem/Components + Features/Components + Capabilities) FIRST, then frozen read-only. P2-P14 = disjoint
file-ownership clusters run in parallel (Wave 2). P15 = compile+test+consolidated report+device-QA checklist.
Sharing split P11 (owner/approval/recipient) vs P12 (QuickLink+QuickView+SharedWithMe). AutoFill (P14) uses
system material NOT tokens — different audit bar. Shared: Localizable.xcstrings orchestrator-owned, phases
emit strings-manifest-phase-XX.md (never edit catalog); shared components edited only by P1.

Builds on [[vaultify-loox-design-dna-controlled-reveal-plan]] (Home/ItemDetail/Search/Unlock already reworked
→ re-reviewed with fewer expected findings). In-code audit gates per phase: grep font/radius/padding/color/
haptics/frame. Presentational fixes ONLY on security-critical clusters (sharing, gate, quickview).
</content>
