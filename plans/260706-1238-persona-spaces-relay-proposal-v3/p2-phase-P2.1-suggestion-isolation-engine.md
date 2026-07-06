# P2.1 — Pure persona suggestion + isolation engine (VaultifyCore)

## Context links
- Canonical: `proposal-v3-locked-decisions.md` — INV-R03. Overview: `p2-plan.md`.
- Consumes P1 type `PersonaIsolationPolicy` (`VaultifyCore/Models/Persona.swift:12-14`).

## Overview
- **Priority:** P2 · **Status:** pending · **Depends on:** — (foundation)
- Greenfield, pure, `nonisolated`, unit-tested. One implementation shared by app (P2.2/P2.4) and the
  memory-tight AutoFill extension (P2.3) — DRY. No SwiftData / no I/O in this file.

## Key insights
- INV-R03 hard-excludes ONLY `strictAnonymous`. `isolated` = prefer own persona but keep others (down-rank).
  `standard` = allow all. Encoding this once, purely, is the whole point of a dedicated engine.
- Candidates must carry their **source persona id** so exclusion is decidable. A candidate with
  `sourcePersonaID == nil` means the global/default identity (NOT persona-owned) → excluded under
  strictAnonymous alongside other personas.

## Requirements
- Functional: given tagged candidates + active persona id + policy, return ordered, de-duplicated
  username/email strings. strictAnonymous removes every candidate not owned by the active persona.
- Non-functional: pure value types, `Sendable`, `nonisolated`; no allocation-heavy work (extension memory).

## Architecture / data flow
`[UsernameCandidate]` (built by callers) → `PersonaUsernameSuggester.suggestions(...)` → `[String]`.

```swift
// VaultifyCore/Models/PersonaSuggestion.swift
nonisolated struct UsernameCandidate: Equatable, Sendable {
    enum Source: Int, Equatable, Sendable { case activePersonaProfile, defaultIdentity, recent }
    var value: String            // email or username
    var sourcePersonaID: String? // nil = global/default identity (not persona-owned)
    var source: Source
    var lastUsedAt: Date?
}

nonisolated enum PersonaUsernameSuggester {
    /// Ordered, de-duplicated suggestions for the active persona.
    /// strictAnonymous → HARD-EXCLUDE any candidate whose `sourcePersonaID != activePersonaID`
    /// (including nil / global default). isolated → keep all but rank own-persona first.
    /// standard → rank own-persona, then default identity, then recents by recency.
    static func suggestions(candidates: [UsernameCandidate],
                            activePersonaID: String,
                            policy: PersonaIsolationPolicy) -> [String]
}
```
Ranking key (ascending → best first): `(source.rawValue, ownPersona ? 0 : 1, -lastUsedAt)`; strictAnonymous
filters `sourcePersonaID == activePersonaID` BEFORE ranking. Dedup by `value.lowercased()`, keep first.
Drop empty/whitespace-only values.

## Related code files
- **Create:** `VaultifyCore/Models/PersonaSuggestion.swift` (<120 LOC)
- **Create:** `VaultifyTests/PersonaSuggestionTests.swift`
- **Read for pattern:** `VaultifyCore/Models/RotationStatus.swift` (pure `nonisolated` logic + tests exemplar).

## Implementation steps
1. Add `PersonaSuggestion.swift` with `UsernameCandidate` + `PersonaUsernameSuggester`.
2. Implement pure filter → rank → dedup. No `import SwiftData`; `import Foundation` only.
3. `tuist generate --no-open` (new file must enter both target globs).
4. Add unit tests (below). Run: `xcodebuild test ... -only-testing:VaultifyTests/PersonaSuggestionTests`.

## Todo
- [ ] `UsernameCandidate` + `Source`
- [ ] `suggestions(...)` filter/rank/dedup
- [ ] `tuist generate`
- [ ] `PersonaSuggestionTests` green via `make check` compile + test

## Success criteria
- strictAnonymous: candidates from persona B and the global default (`sourcePersonaID == nil`) are
  **absent** from output (assert `result` contains only persona-A values) — INV-R03 #5.
- standard: own-persona profile ranks before default identity before recents; dedup case-insensitive.
- isolated: other-persona candidates present but never before an own-persona candidate.
- Pure: identical input → identical output; no main-actor requirement (compiles `nonisolated`).

## Risk assessment
- **Low L × Med I:** over-engineering the scorer. Mitigation: KISS — a single sort key + filter; no weights/config.
- **Low:** enum `Source.rawValue` ordering silently drives ranking. Mitigation: explicit `Int` raw values + a test pinning order.

## Security
- No secrets, no I/O. Values are usernames/emails already destined for a form field; engine only reorders/filters.

## Next steps
Unblocks P2.2 (repository builds candidates + calls engine) and P2.3 (extension mirrors policy; prefill
uses the same exclusion rule).
</content>
