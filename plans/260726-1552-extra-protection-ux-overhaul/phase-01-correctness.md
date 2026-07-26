# Phase 01 — Correctness: ciphertext must never surface

## Files
- `VaultifyAutoFill/AutoFillView.swift` — filter guard2/SecretGuard from the credential hand-off (both call sites); protected rows stay listed but disabled with a lock note.
- `VaultifyCore/CredentialIdentityService.swift` — skip QuickType registration for protected passwords.
- `Vaultify/Features/ItemDetail/ItemDetailScreen.swift` — hide the bottom Copy Password cluster when the password field is protected.
- Row/subtitle providers (Home persona subtitle, item list row subtitle, search rows) — mask sealed values (`SecretGuard.isProtected`) instead of rendering ciphertext. Locate via grep for subtitle derivation (`PersonaDisplay`, `ItemRow*`).
- `Vaultify/Services/Watchtower/PasswordAudit.swift`, `Features/Watchtower/WatchtowerStrengthScreen.swift` — exclude guard2 values from grading/breach hashing.
- `Vaultify/Security/VaultSession+Level2.swift` + `VaultSession.swift` — new `AuthError.wrongExtraPassword` ("Incorrect Extra Password." / VI "Mật khẩu cấp 2 không đúng.") instead of `wrongPassword` mapping.
- `Vaultify/Features/ItemDetail/ProtectFieldSheet.swift:104` — localize the fallback error.
- `Vaultify/Services/ImportExport/VaultBackup.swift` — encrypted backup carries `wrappedL2SK/l2Salt/l2Kdf` (optional fields, backward compatible both ways); restore writes them into `VaultKeyBundle` when absent locally. CSV: `[protected]` placeholder instead of ciphertext.

## Validation
- Unit: SecretGuard mask helper; backup round-trip with and without L2 fields.
- Sim: protect email + password fields → walk Home/list/search/detail/copy → zero `v2g:` anywhere; AutoFill list shows the item as locked and never fills ciphertext.

## Risk
- Backup format change: additive optional keys only; decode tolerates absence.
