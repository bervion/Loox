---
phase: 3
title: "Onboarding Identity Step"
status: pending
priority: P2
effort: "0.5d"
dependencies: [1]
---

# Phase 3: Onboarding Identity Step

## Overview
Add a "What should we call you?" step to first-run that seeds the mandatory default identity from a
display name.

## Requirements
- Functional: new onboarding step collects a display name; on submit, a `.identity` item is created
  (title = display name, Full Name field = display name) and marked default. Best-effort (never blocks
  setup if creation fails, like the "My Vault" folder seed).
- Non-functional: seed logic is a pure, testable function; all new UI strings localized EN + VI.

## Architecture
- Extract creation into a pure helper so it is unit-testable without UI:
  `IdentitySeed.make(displayName:) -> VaultItem` building from `ItemCategory.identity.fieldTemplate`,
  filling Full Name + title, `isDefaultIdentity = true`.
- Insert a `Step.name` case in `OnboardingFlow` (after `.create`, before `.emergencyKit`, OR after
  `.theme` — pick a spot that reads naturally; recommend right after `.create` so identity exists early).
- On submit: `try? env.repository.add(IdentitySeed.make(displayName:))` then advance. Empty name →
  fall back to a localized default title (e.g. "Me") so the invariant "≥1 identity" always holds.

## Related Code Files
- Create: `VaultifyCore/Models/IdentitySeed.swift` (pure builder; `nonisolated`).
- Modify: `Vaultify/Features/Onboarding/OnboardingFlow.swift` — add `.name` step + view; call seed.
- Create: `Vaultify/Features/Onboarding/NameStepView.swift` (small input step, DS tokens, themed).
- Modify: `Localizable.xcstrings` — new strings (EN + VI): step title/subtitle, placeholder, default name.
- Create (test): `VaultifyTests/IdentitySeedTests.swift`.

## Implementation Steps
1. **Tests first** (`IdentitySeedTests`):
   - `testSeedUsesDisplayNameAsTitle` — `make("An")` → title "An".
   - `testSeedFillsFullName` — Full Name field value == "An".
   - `testSeedMarkedDefault` — `isDefaultIdentity == true`.
   - `testSeedFallbackOnEmpty` — `make("")` (or whitespace) → non-empty localized fallback title.
   - `testSeedCategoryIsIdentity` — category == `.identity`.
2. Implement `IdentitySeed.make`.
3. Add `NameStepView` + wire `.name` into `OnboardingFlow`; seed on submit; advance.
4. Add EN+VI strings.
5. Run tests + `make check`. Manual: fresh-install onboarding creates a default identity.

## Success Criteria
- [ ] Seed tests pass.
- [ ] Fresh onboarding always ends with exactly one default identity.
- [ ] All new strings have EN + VI values.
- [ ] `make check` green.

## Risk Assessment
- Whitespace-only / emoji names → fallback covers empty; trim before use.
- Step placement affecting flow animation — verify the `.animation(value: step)` transition still reads
  well; keep step enum order sensible.
- Re-onboarding after recovery (`onboardingCompleted = false`) re-runs the step → guard against
  creating a duplicate default if identities already exist (skip seed when `activeIdentities` non-empty).
