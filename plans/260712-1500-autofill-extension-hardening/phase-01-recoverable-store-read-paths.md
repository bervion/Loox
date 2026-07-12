# Phase 01 — Recoverable Store on Read Paths (P3)

## Context Links

- Audit: `plans/reports/from-extension-audit-260712-1453-autofill-extension-security-perf-report.md` §P3
- Crashing init: `VaultifyCore/Store/VaultStore.swift:12-15` (`fatalError` on container failure)
- Recoverable init (existing pattern): `VaultifyCore/Store/VaultStore.swift:21-23`
- Correct consumers today: `VaultifyAutoFill/CredentialProviderViewController.swift:210-216` (`makePasskeyStore`), `VaultifyCore/VaultWriter.swift:43`

## Overview

- **Priority**: P1 (crash on the most common flow)
- **Status**: completed
- The password + OTP read paths construct `VaultStore()` which `fatalError`s on any container-load failure (corruption, migration mismatch, protected-data-unavailable). The passkey and write paths already use `init(recoverable:)` and cancel gracefully. Make the read paths consistent.

## Key Insights

- Verified call sites of the crashing `VaultStore()` reachable from the extension (grep 2026-07-12):
  - `VaultifyCore/VaultReader.swift:29` (`logins`)
  - `VaultifyCore/VaultReader.swift:47` (`username(forItemID:)`)
  - `VaultifyCore/VaultReader.swift:59` (`defaultIdentityUsername`)
  - `VaultifyCore/VaultReader.swift:83` (`totpItems`)
  - `VaultifyCore/VaultReader+Spaces.swift:41` (`activePersonaSpaces`)
- `VaultReader`/`VaultSpaceReader` have NO app-target callers (grep: only `VaultifyAutoFill/*`) — signatures may change freely.
- "Protected data unavailable" is a real appex condition (device locked edge) → must not crash.

## Requirements

- Functional: a store-load failure in any read path ends the flow with a visible error + working Cancel — never a crash, never a silent empty list that masquerades as "no logins".
- Non-functional: no behavior change on the happy path.

## Architecture / Data Flow

`UnlockGate` → content view `.task` → `VaultReader.*` → `VaultStore`. Failure surfaces as a thrown error at the reader boundary; the view catches, shows a message, and leaves the toolbar Cancel (hosted by `UnlockGate`, `UnlockGate.swift:64-66`) as the exit.

## Related Code Files

Modify:
- `VaultifyCore/VaultReader.swift` — `logins`, `username(forItemID:)`, `defaultIdentityUsername`, `autofillPrefillUsername`, `totpItems`
- `VaultifyCore/VaultReader+Spaces.swift` — `activePersonaSpaces`, `defaultSpaceId`
- `VaultifyAutoFill/AutoFillView.swift` — `CredentialListView.task` (`:127-142`)
- `VaultifyAutoFill/OneTimeCodeView.swift` — `.task` (`:39`)
- `VaultifyAutoFill/CreateLoginView.swift` — `.task` (`:64-67`)
- `VaultifyAutoFill/SavePasswordView.swift` — `.task` (`:55-56`)

## Implementation Steps

1. `VaultReader.logins` / `totpItems` / `username(forItemID:)` / `defaultIdentityUsername`: replace `let store = VaultStore()` with `let store = try VaultStore(recoverable: false)`; mark the functions `throws`. `autofillPrefillUsername` stays non-throwing at its current contract only if its callees allow: it composes `username(forItemID:)` + `defaultIdentityUsername` — make it `throws` too (single honest contract; the caller already runs in a `.task`).
2. `VaultSpaceReader.activePersonaSpaces` / `defaultSpaceId`: use `try? VaultStore(recoverable: false)`; on `nil` return `[]` / `nil`. Rationale: these only drive the optional Space picker — the documented fallback is already "Unfiled, never guess" (`VaultReader+Spaces.swift:30-35`), so degrading is correct while the main list path still surfaces the error.
3. `CredentialListView.task`: wrap the three loads in `do/catch`; on error set a new `storeErrorMessage: String?` `@State` and render a centered message ("Couldn't open your vault.") instead of the list. Localize EN+VI in `Localizable.xcstrings`. Do not auto-cancel — the user reads the message, then taps Cancel.
4. Same pattern in `OneTimeCodeView` (list path) and `CreateLoginView`/`SavePasswordView` (space loading uses the degrading `VaultSpaceReader` — only the save action fails hard, and `VaultWriter` already throws, `VaultWriter.swift:43`).
5. Compile check: `tuist generate --no-open` + workspace xcodebuild per CLAUDE.md (no file additions → regenerate optional but run anyway for consistency).

## Todo

- [x] Reader functions → `throws` + recoverable init
- [x] Spaces reader → degrading `try?`
- [x] View-level catch + localized error state (EN+VI) — "Couldn’t open your vault."
- [x] Compile check both targets (make check pass)

## Success Criteria

- Grep shows zero `VaultStore()` (non-recoverable) calls reachable from `VaultifyAutoFill` sources.
- Simulated failure (unit test with a poisoned store URL / in-memory throw shim) produces a thrown error, not a crash.
- Happy-path list unchanged.

## Risk Assessment

- Low. Signature changes are extension-local (verified no app callers). Main risk: forgetting one call site → compile error catches it.

## Security Considerations

- Fail-visible beats fail-empty: an empty list on store failure could push a user to re-create credentials. The error message must not include the underlying error description (log it via `os.Logger` only, non-sensitive category — pattern at `CredentialProviderViewController.swift:212`).

## Next Steps

- Phase 3 moves store *acquisition* out of the readers entirely (one store per presentation); this phase's `try VaultStore(recoverable:)` lines move to the caller then. Keep this phase minimal so the diff is a clean subset.
