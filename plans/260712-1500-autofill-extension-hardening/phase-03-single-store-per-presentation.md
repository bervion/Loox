# Phase 03 — Single VaultStore per Presentation (P2)

## Context Links

- Audit §P2
- Existing single-store precedent: `makePasskeyStore()` `VaultifyAutoFill/CredentialProviderViewController.swift:210-216`, threaded into `PasskeyActionView` (`store:` param, `PasskeyActionView.swift`)
- Redundant containers: `CredentialListView.task` (`AutoFillView.swift:127-142`) triggers `VaultReader.logins` + `SharedCredentialsCache.load` + `autofillPrefillUsername` → after phase 1, 2-3 `VaultStore(recoverable:)` constructions (= 2-3 `ModelContainer`s on the same SQLite file) per presentation

## Overview

- **Priority**: P2
- **Status**: completed
- Container creation is the dominant cold-start cost after Argon2; multiple containers on one store file invite SwiftData contention. Open ONE `VaultStore` per presentation and thread it through every reader/writer call — exactly the pattern the passkey path already uses.

## Key Insights

- Depends on phases 1 and 2 (same functions change: phase 1 made readers throwing, phase 2 changed key type; this phase adds `store:`).
- `SharedCredentialsCache.load` reads its own sealed file in the App Group, NOT `VaultStore` (`AutoFillView.swift:26-28` comment) — verify during implementation; if it holds no `ModelContainer` it needs no `store:` param. The audit's "2-3 containers" counts `logins` + `autofillPrefillUsername` (which itself calls `username(forItemID:)` + `defaultIdentityUsername` = up to 2 more, `VaultReader.swift:70-79`) — so up to 3-4 containers today on the password list path alone.
- `CreateLoginView.save` → `VaultWriter.createLogin` builds another store (`VaultWriter.swift:43`); the same presentation's store should be reused (SwiftData `mainContext` insert+save works on the shared container).
- Store creation needs no Vault Key → create it in the view controller at host time, pass down; failure = graceful cancel (`cancel(code: .failed)`), same as `makePasskeyStore` today.

## Requirements

- Functional: exactly one `ModelContainer` per extension presentation across list/prefill/spaces/save/OTP; passkey flows keep their existing single store.
- Non-functional: measurable cold-present improvement on the password list (phase 6 QA notes before/after timing via signposts or timestamps, best-effort).

## Architecture / Data Flow

```
CredentialProviderViewController.prepare*       (one makeStore() per request)
   └─ AutoFillView(store:) ─► CredentialListView(store:)
        ├─ VaultReader.logins(store:vaultKey:)
        ├─ VaultReader.autofillPrefillUsername(store:vaultKey:)
        └─ CreateLoginView(store:) ─► VaultWriter.createLogin(store:...)
                                    └─ VaultSpaceReader.*(store:vaultKey:)
   └─ OneTimeCodeView(store:) ─► VaultReader.totpItems(store:vaultKey:)
   └─ SavePasswordView(store:) ─► VaultWriter/VaultSpaceReader(store:...)
```

## Related Code Files

Modify:
- `VaultifyAutoFill/CredentialProviderViewController.swift` — generalize `makePasskeyStore()` (`:210`) to `makeStore()`; create + inject in `prepareCredentialList` (`:29`), OTP list (`:39`), QuickType single (`:63`), save sheet (`:97`, `#if compiler(>=6.2)` block)
- `VaultifyAutoFill/AutoFillView.swift`, `CreateLoginView.swift`, `SavePasswordView.swift`, `OneTimeCodeView.swift` — accept + forward `store: VaultStore`
- `VaultifyCore/VaultReader.swift` — all five functions gain `store: VaultStore` param; drop internal store creation (phase 1 lines move to callers)
- `VaultifyCore/VaultReader+Spaces.swift` — same
- `VaultifyCore/VaultWriter.swift:43` — `createLogin(store:...)`, drop internal creation

## Implementation Steps

1. Rename `makePasskeyStore()` → `makeStore()` (keep behavior: `try? VaultStore(recoverable: false)`, log + nil on failure). Update passkey call sites (`:74,151,169` and `+SilentPasskeys.swift:30`).
2. In each `prepare*` entry point that hosts a password/OTP/save view: `guard let store = makeStore() else { cancel(code: .failed); return }`, pass into the view. This REPLACES phase 1's per-reader `try VaultStore(recoverable:)` — readers become non-throwing again where store was the only throw source (`logins`, `totpItems` keep `throws` only if other throw sources remain; simplify to non-throwing taking `store:`).
3. Thread `store` through view initializers; readers/writers use `store.allRecords()` / `store.context` directly.
4. Keep `CredentialRow`'s isolation comment intact (`AutoFillView.swift:26-28`) — shared entries still never touch `VaultStore`.
5. Compile check both targets; run `make test` (unit tests construct in-memory stores — update any test calling changed signatures).

## Todo

- [x] `makeStore()` generalization + entry-point injection (all 5 entry points + passkey fallback re-host reuses the same store)
- [x] Reader/writer/space functions take `store:` (readers back to non-throwing; phase-1 view error state removed — failure now cancels at host time, and the unused "Couldn’t open your vault." xcstrings key was dropped)
- [x] Views forward store
- [x] Tests updated (none called changed signatures), compile check both targets (make check pass)

## Success Criteria

- Grep: zero `VaultStore(` constructions inside `VaultifyCore/VaultReader*.swift` / `VaultWriter.swift`; constructions exist only in `CredentialProviderViewController.makeStore()` (extension) and app-side code.
- One container per presentation confirmed by a DEBUG counter or log line during QA.
- All extension flows smoke-tested.

## Risk Assessment

- Low-medium. SwiftData `mainContext` reuse across list-read then save-write within one presentation is the normal pattern (app uses one repository container). Watch: the save sheet path on iOS 26.2 runs under `#if compiler(>=6.2)` — keep the injection inside the guard so stable-Xcode CI still compiles.
- Store created at host time even if the user cancels at Face ID — acceptable (same cost as today's first reader call; simpler than lazy plumbing). If cold-present regression is measured, fall back to lazy `@State` creation in the first view.

## Security Considerations

- No change to trust boundaries; the store holds ciphertext only. Failure path must not leak the underlying error to UI (log-only, non-sensitive).

## Next Steps

- Phase 6 tests cover reader behavior via `VaultStore(recoverable: true)` in-memory stores (existing `VaultifyTests` pattern: fixed key + in-memory store, e.g. `VaultifyTests/IdentityDataModelTests.swift:6`).
