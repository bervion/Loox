# Linked services implementation handoff

Implemented native SwiftUI and repository/editor contracts for P3. No commit, backend mutation, release, or deployment performed by this worker.

## Owned code

- `VaultifyCore/Models/AliasLinkedService.swift`: canonical sealed-field projection; one alias to multiple Login items; exact trusted address; explicit separate legacy candidate scan; protected/duplicate/unsupported fields excluded.
- `VaultifyCore/Models/AliasWriteback.swift`: guarded linking, exact unlinking, shared readable-field contract for AutoFill; ordinary credentials untouched; Login conflict cannot be overwritten by legacy helper.
- `VaultifyCore/Models/AliasSuggestion.swift`: canonical address priority; unresolved aliases excluded.
- `Vaultify/Data/Repositories/VaultRepository+AliasLinks.swift`: canonical persona-owned read filters, local link, CAS unlink, one-save sealed item/pointer transaction with snapshot rollback; editor baseline and sealed handoff validation; editor removal also clears primary pointer atomically.
- `Vaultify/Data/Repositories/VaultRepository+AliasWriteback.swift`: trusted profile address, activation Login writeback guarded by captured relation revision and primary pointer.
- `Vaultify/Features/Personas/AliasLinkedServicesScreen.swift`: global/per-alias list, service detail, Open login, Manage private email, explicit confirmation unlink, legacy review/adoption and dedicated existing/new Login picker with protection/conflict repair route.
- `Vaultify/Features/Vault/EditorTarget.swift`, `Vaultify/App/UIStateStore.swift`, `Vaultify/Features/Main/VaultShellBehaviors.swift`: exact alias/persona/relation generation survives sealed draft restoration/remount.
- `Vaultify/Features/ItemEditor/ItemEditorScreen.swift`, `LoginEditorSections.swift`: canonical field separate from existing Email/username; no eager binding before save; exact reserved alias retained on error; active reuse remains local; cancel/detach context clears; stale editor cannot restore a removed relation; partial persistence retains editor/retry.
- `Vaultify/Services/Relay/RelayService.swift`: per-alias operation serialization; after-await live identity lookup and narrow live-row checkpoint/status/recipient patch; captured generation blocks stale auto-writeback; successful mint checkpoint precedes cancellation; destination begin/GET use recipient worker's CAS API and vault-key/cancellation validation.

## Integration APIs

- `AliasLinkedServicesScreen(personaID: String, aliasID: String? = nil)`.
- `AliasLoginPickerSheet(aliasID: String)`.
- `repository.linkedServices(for: personaID, aliasID: optionalID)` and `legacyAliasCandidates(for:aliasID:)`.
- `repository.linkAliasToLogin(aliasID:itemID:expectedItemUpdatedAt:expectedAliasRevision:) throws`.
- `repository.unlinkAliasFromLogin(_ snapshot: AliasLinkedService) throws`.
- `EditorTarget.aliasLogin(VaultItem, aliasID: String, personaID: String, relationRevision: UInt64)`.
- `VaultRepository.AliasLinkFailure.userMessage` for composer/activation local writeback recovery.

Root owns `EmailAlias.resolvedAddress`, sealed `relationRevision`, domain mapping stamp/proof, `+Aliases` canonical resolver forwarding, alias root/detail/composer/picker and central catalog. Root added DEBUG `aliasRelationSaveOverride` for deterministic persistence failure injection. Recipient worker owns destination CAS/service/coordinator/GET budget; Relay wrappers integrated without changing signed authorization or App Attest rules.

## Localization and verification

`linked-services-strings.json` contains English, Vietnamese and Japanese values for 31 new keys, ready for root catalog integration. UI uses existing token styles, Polaris icons, native titles, 44pt targets, wrap-capable addresses, quiet destructive controls, existing haptics and local recipient masking with navigation to alias management.

`VaultifyTests/AliasLinkedServicesTests.swift` adds 10 meaningful tests: one-to-many persisted unlink, ordinary legacy explicit adoption, protection/duplicates/conflict, unknown domain, delayed activation/stale editor, atomic editor detach, canonical persona/missing-folder exclusion, injected save-failure rollback and retry, two same-provider accounts, optional draft context round-trip and old decoding. Existing alias writeback/suggestion tests retained.

`swiftc -frontend -parse` of all owned modified/new Swift files passed; `git diff --check` passed. Full workspace compilation/test execution is pending central integration. No runtime UI/device/mail-delivery claim is made. User-facing copy and non-native preview are not evidence of production domain activation.

## Review follow-up corrections

Confirmed High findings corrected before final integration:

- Minted paused/disabled aliases now rotate their destination while still paused, then send signed `createAlias` with the **same** local-part/domain namespace to reactivate. Resume does not enter collision-remint logic. Local `active` follows both acknowledgments; denied routing/resume stays paused and keeps immutable identity. Existing server policy may reject resume in a create-disabled domain; this implementation preserves truthful state rather than changing backend policy.
- Every signed-command admission has an exactly-once deferred terminal outcome through root's generic capability token API. Cancellation in escrow, attestation and transport remains `CancellationError`; local pre-transport failures release the probe without claiming a relay outage. Successful relay responses report reachability without overwriting operator mode. Root independently changed `RelayAPIClient` to preserve URLSession cancellation.
- Qualified `ActionAuthorization.none` explicitly in the canonical/legacy helpers, eliminating the Optional.none inference that rejected explicit `.none` policies.
- Sealed `DraftState.originalItem` preserves the actual pre-edit baseline. A restored existing Login can save intentional unsaved link/unlink changes, while a real concurrent unlink still rejects stale writeback. Older missing-baseline snapshots decode and use the existing fail-closed comparison/reopen recovery.

Added `RelayLifecycleSafetyTests.swift` with 7 service-level tests for exact rotate→same-namespace resume command ordering, rejection/route failure without remint or false active, and half-open terminal behavior for escrow, App Attest and URL cancellation plus non-transport escrow failure. Expanded `AliasLinkedServicesTests` with explicit nil/.none allow and reauthenticate/level2 deny, AES-sealed restored existing Login link/unlink saves, and concurrent unlink rejection. DEBUG-only dependency overrides are absent from Release and have no UI/environment path; unit tests avoid live CloudKit/App Attest/network calls. No new localization keys.

Syntax parsing and `git diff --check` passed after these edits. Full compilation/tests remain owned by the integration tester; do not interpret the added tests as executed results until its receipt is available.
