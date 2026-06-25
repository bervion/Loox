# Unit Test Phase 1 Verification Report

**Date:** 2026-06-25  
**Tester:** QA Lead  
**Context:** Verify no regression from Phase 1 AutoFill changes (biometric-key migration, SettingsStore flag, App-Group language mirror, KeychainStore accessGroup param)

---

## Test Execution Summary

| Metric | Value |
|--------|-------|
| **Total Tests Run** | 86 |
| **Tests Passed** | 82 |
| **Tests Failed** | 4 |
| **Execution Time** | 0.585 seconds |
| **Result** | **FAILED** |

---

## Failing Tests

All 4 failures are in `ThemeEngineTests` suite and are **pre-existing**, NOT related to Phase 1 changes.

### Test 1: `testAccentPresetsGetReadableForeground()`
- **Status:** FAILED (3 assertion failures within single test)
- **Location:** `VaultifyTests/ThemeEngineTests.swift:78`
- **Failures:**
  1. Blue dark on-accent contrast: **3.201** < **4.5** (WCAG AA)
  2. Indigo dark on-accent contrast: **3.168** < **4.5** (WCAG AA)
  3. Teal light on-accent contrast: **4.242** < **4.5** (WCAG AA)

### Test 2: `testBuiltinAccentForegroundMeetsWCAGAA()`
- **Status:** FAILED (1 assertion failure)
- **Location:** `VaultifyTests/ThemeEngineTests.swift:66`
- **Failure:**
  - Night theme on-accent contrast: **3.201** < **4.5** (WCAG AA)

---

## Analysis

### Root Cause

The failing tests check that accent color presets meet **WCAG AA contrast ratio (4.5:1)** when calculating the foreground text color. However, the `RGBMath.onAccent()` function (ColorHex.swift:48-50) uses a **3.0:1 threshold**:

```swift
static func onAccent(_ background: UInt32) -> UInt32 {
    contrastRatio(0xFFFFFF, background) >= 3.0 ? 0xFFFFFF : 0x000000
}
```

This threshold is sufficient for **large/bold UI text** (WCAG A) but does **not** guarantee **AA (4.5:1)**.

### Accent Color Values (Unchanged)

Tested colors are identical to the theme-simplify commit (d618e2c):
- Blue dark: `0x4C8DFF` → white text contrast ratio 3.20
- Indigo dark: `0x8B80FF` → white text contrast ratio 3.17
- Teal light: `0x2FD0BF` → white text contrast ratio 4.24 (fails at 4.5 boundary)

### Phase 1 Unrelated

Phase 1 changes are **orthogonal** to accent colors:
- ✅ BiometricKeyStore keychain access group (`accessGroup` param)
- ✅ SettingsStore flag for one-time migration
- ✅ App-Group language mirroring
- ✅ Localization catalog bundling in extension

**None of these changes affect:**
- `AccentColor.swift` hue definitions
- `RGBMath.contrastRatio()` or `RGBMath.onAccent()` logic
- Theme palette or accent foreground calculation

---

## Other Test Suites - All Passing

| Suite | Tests | Status | Notes |
|-------|-------|--------|-------|
| VaultBackupFolderTagsTests | 4 | ✅ PASS | CSV import/export, folder & tags |
| VaultRepositoryFolderTests | 6 | ✅ PASS | Folder CRUD, item counting, recent ordering |
| **Other Theme Tests** (19/23) | 19 | ✅ PASS | Settings codec, accent recolor, auto-night, mesh math, legacy migration |

No regression in test coverage for Phase 1 logic (keychain, biometric, settings, migration).

---

## Conclusion

**Status: FAILED (pre-existing issue)**

The 4 failing tests are a **pre-existing design/implementation mismatch** introduced when the Design System palette was simplified (commit d618e2c, 2026-06-17). The accent presets do not meet the WCAG AA contrast requirement imposed by the test assertions.

**No regression from Phase 1 AutoFill changes.** All functional logic for biometric unlock, keychain sharing, and localization is covered by passing tests elsewhere.

---

## Recommendations

### Option A: Fix Accent Colors (Design Impact)
Adjust the 3 failing presets to guarantee 4.5:1 contrast in dark mode:
- Blue: lighten from `0x4C8DFF` to higher luminance
- Indigo: lighten from `0x8B80FF` to higher luminance  
- Teal (light): darken from `0x2FD0BF` slightly to push above 4.5

Impact: Live-theme appearance changes (requires design review).

### Option B: Adjust `onAccent()` to AA Threshold (Implementation Fix)
Change the 3.0 threshold to 4.5:1 in `RGBMath.onAccent()`. Risk: dark accents may flip to black text, which may not match the iOS convention for colored buttons (white text preferred on bright saturated colors).

### Option C: Relax Test Expectations (Pragmatic)
If the current accent palette is intentional and the 3.0 threshold is by design, update test assertions to reflect actual capability:
```swift
XCTAssertGreaterThanOrEqual(ratio, 3.0)  // WCAG A for large/bold UI
```
Rationale: app buttons use accents as bold/large controls, so AA is not a strict requirement.

---

## Unresolved Questions

1. Was the test intentionally written at AA (4.5:1) as a future aspiration, or is the accent palette the issue?
2. What is the design intent: are the 7 presets final, or will they be adjusted post-launch?
3. Should `onAccent()` prioritize iOS button convention (white on saturated colors) or WCAG AA accessibility?

