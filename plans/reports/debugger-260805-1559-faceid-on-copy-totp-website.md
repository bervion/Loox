# Face ID prompt when copying 2FA code / Website — root cause

Reported: tapping to copy a 2FA code or a Website on a login item raises Face ID.
Status: root cause confirmed by code trace. Fix NOT applied (separate concern from the story-intro branch).

## Root cause (one line)

The `.login` registry template declares field descriptors for **only** `.username` and `.password`, but `LegacySemanticsInference` stamps `.totp` and `.website` roleIDs on login fields — so those two roles resolve to NO descriptor, which the resolver treats as an **unknown role** and answers with `.reauthenticate` (device-owner auth) + `.secret` sensitivity.

## Trace

1. `VaultifyCore/Types/LegacySemanticsInference.swift:52-57` — for a `.login` item, kind is authoritative: `.totp` → roleID `.totp`, `.url` → roleID `.website`. Runs **in memory on every decode**, so every existing login item is affected (no migration needed to trigger it). Pinned by `VaultifyTests/LegacySemanticsInferenceTests.swift:19-20`.
2. `VaultifyCore/Types/ItemTemplateRegistry.swift:48-69` — the `.login` definition's only `TemplateFieldDescriptor`s are `.username` and `.password`. Comment at `ItemCategory.swift:83-86` explains why the *default field set* excludes Website/TOTP — but the descriptor list is ALSO the role→policy table, and that is the conflation that caused this.
3. `ItemTemplateDefinition.descriptor(for:)` (line 132) searches only declared section fields → returns nil for `.totp` / `.website`.
4. `ItemCapabilityResolver.capabilities(for:in:)`:
   - line 73 `hasUnknownRole = field.roleID != nil && registryDescriptor == nil` → **true**
   - line 81 `if hasUnknownRole { authorization = .reauthenticate }`
   - line 76 `fallbackSensitivity(unknownRole: true)` → `.secret`
5. `Vaultify/Features/ItemDetail/ItemDetailScreen.swift:574-576` passes `requiresReauth: caps.revealAuthorization == .reauthenticate` into `DetailFieldRow`.
6. `DetailFieldRow.copy()` (line 374) → `authorizeThen` (line 362) → device-owner auth. **The reported Face ID prompt.** Same gate hits reveal and Large Type.

Only `.login` is affected: the `.sshKey` and `.recoveryCodes` templates DO declare every role their inference can assign (`ItemTemplateRegistry.swift:150-170, 189`), and `.note` declares `.noteBody`.

## Other symptoms from the same defect

- `LooxLinkEnvelope.swift:39` filters fields by `caps.quickShare`, and `valueLeavable` requires `!hasUnknownRole` → **Website and 2FA are silently dropped from a Quick View share**.
- `caps.searchIndex` false and `caps.plaintextExport` false for both fields. No consumers exist yet (grep found none outside the resolver), so no user-visible effect today — but both would be wrong the moment search indexing or the CSV path adopts the resolver.

## Fix (parity-exact, 2 lines)

Add the two missing descriptors to the `.login` template's core section, marked `isDefault: false` so the **default field set at creation does not change** (`TemplateFieldDescriptor.isDefault` doc, `ItemTemplateDefinition.swift:24-26`; init defaults `isDefault: true`, so it must be passed explicitly):

```swift
TemplateFieldDescriptor(roleID: .website, label: "Website", kind: .url,
                        sensitivity: .private, isDefault: false),
TemplateFieldDescriptor(roleID: .totp, label: "One-time Code", kind: .totp,
                        protected: true, sensitivity: .secret, isDefault: false),
```

Why these exact values restore pre-inference behavior:
- `actionAuthorization` defaults to `.none` → no Face ID, matching how these fields behaved before roles existed.
- Website: created unprotected (`LoginEditorSections.swift:226`) → old `fallbackSensitivity` was `.private`.
- One-time Code: created `protected: true` (`VaultBackup.swift:175`) → old `fallbackSensitivity` was `.secret`. Labels match the strings the app already creates.

## Missing test that would have caught it (add with the fix)

No test asserts the invariant that binds the two tables. Add: for every `(category, fieldKind)` pair `LegacySemanticsInference.provableRole` can return a role for, the template mapped from that category MUST return a descriptor for that role. That fails today on login/totp and login/url, and would catch the next role added to inference without a matching descriptor.

## Unresolved questions

1. Apply on a separate branch (recommended — it is unrelated to the story intro PR #198 and is security policy)?
2. Should the TOTP descriptor's sensitivity be `.secret` (parity, recommended) or `.keyMaterial` (stricter: would also block Quick Share of the 2FA field)?
3. Was `.reauthenticate`-on-unknown-role ever intended to reach fields the app itself creates, or should the fail-closed default be narrowed to genuinely unrecognised roles (fields from a future app version)? The current rule punishes the app's own incomplete registry.
