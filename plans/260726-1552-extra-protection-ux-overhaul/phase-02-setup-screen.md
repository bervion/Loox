# Phase 02 — Level-2 setup/manage screen rebuild

## Design (CreateMasterPasswordView idiom, plain background)
- Hero: `LooxSwirlAnimationView(mode: .reveal, centerIcon: "dt_shield_keyhole", centerTint: accent)` ~150pt — one-shot dots radiate then freeze (Reduce Motion: settled frame). Same composition as the Security empty state.
- screenTitle + subhead copy per state (not set / set).
- Capsule password group (extracted from CreateMasterPasswordView as a shared component): field + confirm w/ divider, single eye reveals both, inline 22pt strength ring (no "bits" label anywhere).
- `BrandCapsuleCTA` pinned bottom ("Set Extra Password" / "Change Password").
- NOT SET state: hero + explainer + set form. Success: haptic + brief settled confirmation state, then the screen flips to the SET state (no silent pop).
- SET state: status card ("Extra Password is on" + n protected fields across m items), actions: Change (inline expand current+new+confirm), **Turn Off** (destructive row).
- Turn Off flow: enter current password → confirm dialog stating count of fields that will return to normal → decrypt-in-place all `.level2` fields via repository walk → success feedback. New session API `removeLevel2Password(current:)` in `VaultSession+Level2.swift` (verify unwrap, decrypt fields, clear `wrappedL2SK/l2Salt/l2Kdf`, drop `level2Key`).
- Security row (`SecuritySettingsView`) shows state: "On" / "Off" trailing text.

## Files
- `Vaultify/Features/Settings/Level2SettingsView.swift` (rebuild)
- `Vaultify/Features/Components/` — extracted `PasswordCreationGroup` (capsule + strength ring) shared with onboarding
- `Vaultify/Security/VaultSession+Level2.swift`, `VaultifyCore/Keychain/VaultKeyBundle.swift` (clear path)
- `Vaultify/Features/Settings/SecuritySettingsView.swift`, `MacSettingsView.swift`
- `Vaultify/Localizable.xcstrings` — all new copy EN+VI (VI: "Mật khẩu cấp 2")

## Validation
- Light/dark/VI/Reduce Motion/iPhone 11/iPad; macOS slice compiles.
- Set → protect → turn off → fields plaintext again; count in dialog matches.
