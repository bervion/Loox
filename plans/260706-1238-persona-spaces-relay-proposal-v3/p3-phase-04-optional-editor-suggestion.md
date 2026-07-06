# P3 Phase 4 — OPTIONAL / DEFERRED: login-editor alias suggestion (flag-gated)

**Context:** `p3-plan.md` · Phases 2–3. **Status: DEFERRED (YAGNI).**
**Pattern sources:** `VaultifyCore/VaultReader.swift:70-79` (`autofillPrefillUsername`),
`Vaultify/Data/Repositories/VaultRepository+PersonaContext.swift:55-77` (`usernameSuggestions`).

## Why deferred (autonomous decision)
Binding a per-site alias to a login already exists in Phase 3 (alias editor's login picker).
The reverse direction — offering a reserved alias as the email/username when *creating a login*
— has near-zero value while the relay is off: it would write a **non-working** address into a
real credential, and it widens the INV-R03 isolation surface (the create-login editor and the
AutoFill extension both read persona context). Per YAGNI + the trust-safety framing, do NOT
build this in P3. Documented here so the intent is explicit, not forgotten.

## If/when built (P4B+, relay live)
Gate strictly behind `RelayFeature.activeAliasesEnabled`:
- In-app `ItemEditorScreen` create-login: add reserved/active aliases of the **active persona
  only** to the username suggestion list (extend `usernameSuggestions()` — never cross-persona;
  strictAnonymous still excludes, INV-R03).
- Extension (`VaultReader.autofillPrefillUsername`): only suggest an alias once it is `.active`
  (a reserved-only alias is not a deliverable address). Respect the QuickType plaintext-index
  threat model already documented in P2.
- Surface each alias via `AliasAddress.display` (full `@domain` valid only when active).

## Related code files (future)
- `Vaultify/Data/Repositories/VaultRepository+PersonaContext.swift` — extend `usernameSuggestions`.
- `VaultifyCore/VaultReader.swift` — extend `autofillPrefillUsername` (flag + `.active` gate).
- `Vaultify/Features/ItemEditor/*` — surface the picks.

## Success criteria (future)
- No alias suggestion appears while `RelayFeature.activeAliasesEnabled == false`.
- No cross-persona alias ever suggested (INV-R03); strictAnonymous suggests nothing borrowed.

## Risk if built prematurely
Writing a dead alias address into a live login → user sends mail to a black hole → data loss +
trust breach. This is exactly the failure the feature flag exists to prevent — hence deferral.

## Next steps
Revisit only after P4B (receive-only ingress verified). Until then, no code.
