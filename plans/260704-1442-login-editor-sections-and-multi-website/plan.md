# Login editor sections + multi-website AutoFill

Restructure the **Login** item editor into sections and support multiple websites that all
feed AutoFill. Decisions (user-confirmed): Login only • Credentials = Username + Password +
One-time code, linked passkeys shown read-only • AutoFill matches ALL websites • Notes always
visible, single multiline, fixed bottom.

## Sections (Login only; other categories keep the current flat editor)
1. **Credentials** — username, password, TOTP fields + read-only rows for any linked passkey
   (passkeys are OS-created via WebAuthn, matched by relyingParty → website host; not editable here).
2. **Websites** — every `.url` field; add/remove multiple; each row is a website.
3. **Custom Fields** — everything else (add field [excl. url/note/attachment kinds] + attachment).
4. **Notes** — the single `.multiline` field, always present, fixed at bottom.

## Multi-website AutoFill (data + matching)
- `VaultItem`: `urlValues` / `autofillHosts` (all non-empty website hosts, deduped); `autofillHost`
  becomes `autofillHosts.first` (favicon/subtitle still use first `urlField`).
- `matchesAutoFill` / `matchesRelyingParty` check ANY host (extension in-app matching + passkey attach).
- `CredentialIdentityService`: publish one password identity (and one OTP identity) PER host.

## Files
- `VaultifyCore/VaultReader.swift` (VaultItem multi-host extension + matchers)
- `Vaultify/Services/CredentialIdentityService.swift` (per-host identities)
- New `Vaultify/Features/ItemEditor/LoginEditorSections.swift` (the 4 sections)
- `Vaultify/Features/ItemEditor/ItemEditorScreen.swift` (login→sections branch; ensure note field)
- `Localizable.xcstrings` (Credentials/Websites/Custom Fields/Notes/Add Website — EN + VI)

## Status — DONE (BUILD SUCCEEDED, app + extension)
- [x] P1 VaultItem multi-host + matchers (urlValues/autofillHosts; matchesAutoFill/RelyingParty any-host)
- [x] P2 CredentialIdentityService per-host (password + OTP identities flatMap over hosts)
- [x] P3 LoginEditorSections component (index-based bindings by field kind)
- [x] P4 ItemEditorScreen wiring + note-field ensure (login→sections; ensureLoginNoteField)
- [x] P5 Localization EN+VI (Credentials/Websites/Custom Fields/Add Website/Add a note added to xcstrings)
- [x] Build check

## Notes / trade-offs
- Login grouped sections drop drag-reorder (KISS; not requested). Non-login keeps reorder.
- Empty note field (label "Note") persists on save; detail hides empty values.
- Changing a field's kind in-row reclassifies its section (expected with kind-based grouping).
