# Phase 01 — Profile shell + navigation restructure

Type: reuse · Depends: — · Ships the layout that 02–06 hang off.

## Context
- Current `Vaultify/Features/Profile/ProfileScreen.swift` = avatar header + `personaSection` + `identitySection` (`ProfileSectionCard`) + `paymentSection` (`ProfileSectionCard`). Pushed onto Home's UINavigationController via `navigator.push { ProfileScreen() }`.
- Target: grouped nav rows → detail screens + bottom Switch button (mockup).
- Reuse the grouped-row look from `ItemsScreen.navRow` and grouped-card helpers; icons from `Icons` (Polaris).

## Requirements
- **Header**: `ProfileAvatarView` + **name** (identity "Full Name" → fallback `persona.displayName`) + **email** (`identityUsername(forPersona:)`). Name/email are NEW under the avatar.
- **Group 1** card: `Personal Information` → `PersonalInformationScreen` (P02); `Payment` → `PaymentCardsScreen` (P03).
- **Group 2** card: `Loox` → `LooxHubScreen` (P04); `Family` → `FamilyScreen` (P05).
- **Group 3** card: `Devices` → `DevicesScreen` (P06).
- **Bottom**: full-width `Switch profile` button → present `PersonaSwitcherScreen` (existing).

## Files
- Modify: `ProfileScreen.swift` (recompose body; keep the avatar photo picker).
- New (if not cleanly reusable from Items): `Vaultify/Features/Profile/ProfileNavRow.swift` — leading Polaris tile + title + optional trailing value + chevron.
- The identity/payment inline cards move OUT into P02/P03 screens (don't leave duplicate entry points).

## Steps
1. Header VStack (avatar + name + email), centered.
2. Grouped cards (`Radius.lg`, `elevatedBackground`, `.elevation(.level1)`) with nav rows; wire destinations. Until a target phase merges, route its row to a minimal localized "Coming soon" placeholder.
3. Bottom Switch-profile button (`.themedProminent` / tinted, full width).
4. Localize EN + VI: "Personal Information", "Payment", "Loox", "Family", "Devices", "Switch profile" (+ trailing values like "N cards"). Add any missing keys.
5. Remove old persona/identity/payment inline sections once P02–P04 exist.

## Validation
- `make check`; light/dark + Reduce Transparency; 44pt targets; VoiceOver reads each row.
- Switch-profile updates the header live (persona change).

## Risks
- Don't drop existing capabilities during the move — edit identity, switch identity, edit card, switch persona, Private Email link all relocate into P02/P03/P04, they don't disappear. Keep a migration checklist.
