# Phase 03 — Lifecycle wiring + decouple Persona

Priority: P0 · Status: pending · Depends: Phase 01

## Triggers
1. Launch-after-unlock — fire once per process when session first reaches `.unlocked`.
   Non-blocking `Task`. Hook point: `RootView.handleScenePhase(.active)` where
   `env.session.state == .unlocked` already gates the repo reload (`RootView.swift:67`),
   guarded by a one-shot flag; or observe session transition.
   `Task { await env.controlPlaneRefresher.refreshIfNeeded(trigger: .launchAfterUnlock) }`
2. Foreground — every `.active`:
   `Task { await env.controlPlaneRefresher.refreshIfNeeded(trigger: .foreground) }`
   Coordinator's freshness + dedupe prevent redundant fetches (INV-CP-05).

Both non-blocking — MUST NOT block unlock/render/AutoFill/core vault (INV-CP-02).

## Decouple Persona
`PersonaAliasesScreen.probe()` — keep the email-capability health probe, but its
manifest/domain-registry refresh is no longer authoritative. Route through the
coordinator (`refreshIfNeeded(.manual)`) or drop the direct calls; either way, no
feature screen is the source of control-plane freshness (INV-CP-01).

## Reactive UI (already satisfied — verify)
`CapabilityStore` is `@Observable`; `ItemDetailScreen.quickViewEntryVisible` reads
`env.capabilities.quickViewExposure` → SwiftUI re-renders when apply() lands after a
background refresh. No screen reopen needed (INV-CP-04/11). No change required; add a
UI test.

## Files
- `Vaultify/App/AppEnvironment.swift` (own the refresher; pass clients)
- `Vaultify/App/RootView.swift` (two triggers)
- `Vaultify/Features/Personas/PersonaAliasesScreen.swift` (route via coordinator)

## Todo
- [ ] AppEnvironment owns SignedControlPlaneRefresher
- [ ] RootView launch-after-unlock (one-shot) + foreground triggers
- [ ] PersonaAliasesScreen refresh via coordinator, not authoritative
- [ ] Verify reactive exposure update on ItemDetailScreen

## Success
- Never opening Persona → Quick View still appears after background refresh.
- Launch+foreground → one request per document.
