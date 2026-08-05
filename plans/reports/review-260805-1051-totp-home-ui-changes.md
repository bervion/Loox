# TOTP Home UI changes — implementation + review report (260805)

## Scope (owner request)
1. Home TOTP carousel: cards clipped at section inset → full-bleed edge-to-edge scroll.
2. "View All" 2FA: bottom sheet grid → pushed screen, full-width rows, search bar on top.
3. "Recently Used" Home section: title outside card → inside card (matched Needs Attention / All items anatomy). Favorites had identical anatomy → moved too (consistency; revert = 1 line if unwanted).

## Changes
- `HomeScreen.swift` — totpSection viewport bleeds `-Space.gutter`, content re-insets `+Space.gutter` (resting cards stay header-aligned); `showTotpList` sheet removed → `openTotpList()` push (navigator / homePath); `groupedCard` + external header → `titledGroupCard(title:)`; both entry points (section "View All" + Quick Actions 2FA tile) push.
- `VaultRoutes.swift` — new `VaultRoute.totpCodes` (Codable-safe, no payload) → `TotpListScreen()`.
- `TotpListScreen.swift` — rewritten: List of rows + `.searchable` (navigationBarDrawer `.always` on iOS, `.automatic` macOS), token-AND filter over `searchText`, themed row background, empty + no-results states, `.analyticsScreen("totp_list")`. Sheet variant (`presentedAsSheet: true`) kept for iPad/Mac sidebar quick action (VaultShellBehaviors).
- `TotpRowView.swift` (new) — favicon 40 + title/username + ticking code (title3 bold tabular, ≤5s warning) + ring; tap copies + "Copied" flash 1.1s; privacy-sensitive; VO: identity label, digit-by-digit value, "Double tap to copy" hint, copy announcement.
- `TotpRingView.swift` — Reduce Motion numeric fallback now `.accessibilityHidden(true)` (parity with ring branch).

## Review (workflow: 4 fable lenses → adversarial verify, 12 raw → 9 confirmed → 5 fixed)
Fixed: listRowBackground theming (major), Dynamic Type code truncation — minScale 0.7 + layoutPriority (major), Copied-flash width jitter — resident code under overlay (minor), VoiceOver label/value/hint/announcement (minor), RM ring digit a11y (minor).

## Fixed in follow-up (same branch, owner request)
- **Ring hardcoded 30s period** → new `TOTPGenerator.period(forStoredValue:)`; threaded through ALL countdown surfaces: TotpCardView, TotpRowView, DetailFieldRow ring, LargeTypeView (header ring + refreshTOTP + floating pill). Bonus hardening in `parse(uri:)`: period ≤ 0 → 30 (was ÷0 crash path on malicious/typo QR), digits clamped 1…9 (was UInt32 overflow trap). New `VaultifyTests/TOTPGeneratorTests.swift`: RFC 6238 KAT (t=59 → 94287082), period=60 counter windows (755224/287082), fallback + clamp + secondsRemaining pins.
- **Out of scope**: `RequestCodeView` (ApprovedCodeView) ring keeps period 30 — recipient side of approval sharing; true period not on the wire (only `periodEndUnixMs`), fixing = protocol change.

## Not fixed (deliberate)
- **DRY drift** — row duplicates card's copy/format/tick; house idiom already duplicates the search filter. Left per KISS.
- **iPad pane bleed** — full-bleed carousel slices at detail-pane boundary next to sidebar divider (inherent to bleed-in-pane; most apps accept).
- **No tests** for new token filter + route case (nothing existing breaks — verified no test references TotpListScreen/VaultRoute/quickSheet.totpCodes).

## Verification status
- `swiftc -parse` clean on all 5 files. **Full compile NOT run**: machine has Xcode 16.4 + Tuist 3.2.0; repo pins Xcode ≥ 26.5 (`scripts/ci/toolchain-pin.sh`) + Tuist 4.200.1 (`.mise.toml`). `make check` fails at `tuist generate` (manifest type-check timeout on old tuist).
- Localization: all user-facing keys pre-exist in `Localizable.xcstrings` with VI+JA ("2FA Codes", "Search", "Copied", "No 2FA codes", "Recently Used", "Favorites", "Done", "Untitled", "2FA code", "Double tap to copy", empty-state description). Zero new strings.

## Unresolved questions
1. Install toolchain here (mise + tuist 4.200.1 easy; Xcode 26.5 = large download) or compile on the usual dev machine?
2. Favorites in-card title — keep or revert?
3. Schedule the otpauth-period ring fix as its own change?
