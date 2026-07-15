# Phase 02 — Personal Information detail

Type: reuse · Depends: 01

## Context
- Identity = `VaultItem` `.identity`; fields: Full Name, Email, Phone, Address, Date of Birth, ID Number (`VaultifyCore/Models/ItemCategory.swift`).
- Active identity = `env.repository.activeProfileItem` (from `persona.primaryProfileItemID`).
- Switch the identity ITEM = `setProfileItem(item, for: persona)`; pool = `items(for: persona).filter { $0.category == .identity }` (already correct in current ProfileScreen).
- **User decision**: "đổi Identity khác" = pick a different identity ITEM as this profile's card — NOT switch persona (that's the bottom button).

## Requirements
- New `PersonalInformationScreen`: renders the active identity's fields, tap-to-copy, sensitive fields (Phone, ID Number) masked by default; `Edit` → `ItemEditorScreen(target: .edit(item))`.
- Switch-identity affordance (menu/row): lists this persona's identity items → `setProfileItem`; "Create new identity" → `ItemEditorScreen(target: .new(.identity))`.
- Empty state when the persona has no identity item yet.

## Files
- New: `Vaultify/Features/Profile/PersonalInformationScreen.swift`.
- Reuse: `ProfileSectionCard` field rendering (or `DetailFieldRow`), `ItemEditorScreen`.
- Modify: `ProfileScreen` (remove identity inline section — moved here).

## Steps
1. Field list from `activeProfileItem` (reuse existing field-row + mask/copy behavior + clipboard-clear).
2. Switch-identity picker → `setProfileItem`; create-new → editor.
3. Localize new strings EN + VI.

## Validation
- `make check`; picker shows ONLY the active persona's identities (INV-R03); tap-to-copy respects clipboard-clear.
