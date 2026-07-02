---
phase: 4
title: "App UI Passkey Management"
status: pending
priority: P2
effort: "10h"
dependencies: [3]
---

# Phase 4: App UI Passkey Management

<!-- Updated: Validation Session 1 - added passkey coverage in encrypted backup/restore (D6); effort 8h → 10h -->

## Overview
Users can finally SEE and manage their passkeys (F3): passkeys render inside matching login items (D3 attach-to-login) plus a standalone Passkeys screen (Settings) covering the full list and orphans. Delete propagates to the vault and the identity store. Encrypted backup/restore now covers passkeys (D6).

## Requirements
- Functional: passkey section in `ItemDetailScreen` for matching `.login` items; Passkeys screen (grouped by site, detail sheet, delete with confirmation); Settings entry; passkeys included in encrypted backup export/import (NEVER in CSV).
- Non-functional: design-system tokens only (`Space`/`Radius`/`Metric`/`.vaultType`/ThemeRole colors), Polaris SVG icons, 44pt targets, light+dark+Reduce Motion verified, EN+VI localization, files ≤ ~200 LOC (split views).

## Architecture
Read model only — `VaultRepository.passkeys: [PasskeyInfo]` (Phase 3) feeds both surfaces. Item↔passkey linkage reuses the EXISTING host-matching convention instead of a new module (RT-12: the exact suffix rule already ships at `TwoFactorCatalog.swift:74` and the sibling matcher `VaultItem.matchesAutoFill` lives at `VaultReader.swift:87-94`): add `VaultItem.matchesRelyingParty(_:)` as an extension **beside `matchesAutoFill`** with a comment contrasting the two rules (`host == rp || host.hasSuffix("." + rp)`; rpId is registrable-domain; never cross-domain). Deletion: `VaultRepository.deletePasskey` → `PasskeyVault.delete` (injected store) → reload → serialized identity refresh.

## Related Code Files
- Create: `Vaultify/Features/Passkeys/PasskeysScreen.swift` (grouped list, empty state)
- Create: `Vaultify/Features/Passkeys/PasskeyDetailSheet.swift` (rp, userName, createdAt, lastUsedAt, credentialID base64url, delete)
- Modify: `VaultifyCore/VaultReader.swift` (`matchesRelyingParty` extension next to `matchesAutoFill` — NO new matcher file, RT-12)
- Modify: `Vaultify/Features/ItemDetail/ItemDetailScreen.swift` (Passkeys section for matching login items)
- Modify: `Vaultify/Features/Settings/SettingsScreen.swift` (row → PasskeysScreen)
- Modify: `Vaultify/Data/Repositories/VaultRepository.swift` (`deletePasskey(credentialID:)`)
- Modify: `Vaultify/Services/ImportExport/VaultBackup.swift` (optional passkeys array inside the sealed `EncryptedBackup` payload — old backups keep decoding; CSV untouched)
- Modify: `Vaultify/Features/ImportExport/ExportView.swift`, `Vaultify/Features/ImportExport/ImportView.swift` (pass passkeys through export; restore path saves via `PasskeyVault` + identity refresh)
- Create: `VaultifyTests/PasskeyRelyingPartyMatchingTests.swift` (table-driven matcher cases)
- Create: `VaultifyTests/PasskeyBackupRoundtripTests.swift` (export→import fidelity incl. private-key bytes; legacy backup without passkeys still imports)
- Modify: `Vaultify/Localizable.xcstrings` (catalog path — NOT `Resources/`)

## Implementation Steps
1. **Matching**: `VaultItem.matchesRelyingParty(_ rp: String)` beside `matchesAutoFill` (VaultReader.swift:87-94), suffix rule + traps (`notexample.com` !~ `example.com`), lowercase both sides. Comment contrasting with `matchesAutoFill`'s looser rules and `TwoFactorCatalog.swift:74`'s identical rule.
2. **VaultRepository.deletePasskey(credentialID:)**: PasskeyVault.delete → reload passkeys → serialized identity refresh (Phase 3 wiring).
3. **PasskeysScreen**: sections grouped by relyingParty — favicon via existing `FaviconView(urlString:category:size:)` (host-keyed, directly reusable — `FaviconView.swift:6-9`), row = userName + relative lastUsedAt; empty state explains passkeys + how they get created. Entry row in `SettingsScreen` (Polaris passkey/key icon).
4. **PasskeyDetailSheet**: metadata via existing `DetailFieldRow` patterns; destructive delete behind `confirmationDialog` with explicit consequence copy ("Websites will no longer offer this passkey; you may lose access if it's your only sign-in method"). No swipe-delete in lists — deletion only via the sheet (irreversible: private key is destroyed, no trash).
5. **ItemDetailScreen**: for `.login` items with `autofillHost`, render "Passkeys" section listing matches → detail sheet. Section hidden when no matches.
6. **Backup coverage (D6)**: extend the sealed payload of `VaultBackup.EncryptedBackup` with an OPTIONAL passkeys array (full `PasskeySecret`s — the payload is already passphrase-encrypted; decode absent field as empty for legacy backups). Export: include stored passkeys. Import: restore via `PasskeyVault.save` (atomic replace dedupe applies), then serialized identity refresh. CSV export/import NEVER carries passkeys — add an explanatory note in the export UI copy.
7. **Localization**: all new strings EN+VI (`.inAppLocalized` titles, `appString()` runtime).
8. Tests: matcher table-driven (exact, subdomain, unrelated suffix, empty host, case, IDN-lowercase note); backup roundtrip incl. private-key byte fidelity + legacy-backup decode; `make check`, `make test`; visual pass light/dark.

## Success Criteria
- [ ] Login item with matching passkey shows the section; unrelated domains never match
- [ ] Passkeys screen lists all (incl. orphans), detail + delete works, QuickType suggestion disappears after delete
- [ ] Empty state, EN+VI strings, token-driven styling, 44pt targets
- [ ] Encrypted backup export→import round-trips passkeys (signature-capable after restore); legacy backups import cleanly; CSV contains no passkey material
- [ ] Matcher + backup tests green; `make check` + `make test` green

## Risk Assessment
- **Domain-match false positives** are display-linkage only — never used for filling decisions (system supplies rpId at ceremony time). Matcher stays conservative.
- **Delete is irreversible** (private key gone): explicit confirmation copy; sheet-only entry point.
- **Third matching rule drift** (RT-12): avoided by construction — one shared extension, cross-referenced comments.
